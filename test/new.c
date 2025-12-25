#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <net/if.h>        // Tambahkan ini untuk IFNAMSIZ
#include <linux/if_tun.h>  // Tambahkan ini untuk definisi TUN/TAP
#include <netinet/in.h>

#ifndef IFF_TUN
#define IFF_TUN         0x0001
#endif

#ifndef IFF_NO_PI
#define IFF_NO_PI       0x1000
#endif

#ifndef TUNSETIFF
#define TUNSETIFF       _IOW('T', 202, int)
#endif

#define GTPU_PORT 2154
#define BUFFER_SIZE 65536

// Global Variables
bool gtpu_initialized = false;
static int tun_fd = -1;
static int udp_sock = -1;


// Function to create TUN device
int create_tun_device(const char *dev) {
    struct ifreq ifr;
    int fd = open("/dev/net/tun", O_RDWR);
    if (fd < 0) {
        LOG_E(GTPU, "Opening /dev/net/tun failed: %s\n", strerror(errno));
        exit(EXIT_FAILURE);
    }

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, dev, IFNAMSIZ - 1);
    ifr.ifr_flags = IFF_TUN | IFF_NO_PI;

    if (ioctl(fd, TUNSETIFF, (void *)&ifr) < 0) {
        LOG_E(GTPU, "TUNSETIFF failed: %s\n", strerror(errno));
        close(fd);
        return -1;
    }

    LOG_I(GTPU, "Created TUN device %s\n", dev);
    return fd;
}

// Forwarding packet to GTP-U
void forward_to_gtpu(int udp_sock, struct sockaddr_in *remote_addr, char *packet, ssize_t len, uint32_t teid) {
  char buffer[BUFFER_SIZE];
  struct gtp_header *gtp = (struct gtp_header *)buffer;

  gtp->flags = 0x30;  // Menggunakan versi 1 dan protokol GTP
  gtp->message_type = GTP_GPDU;  // Menggunakan GTP GPDU (255)
  gtp->length = htons(len);
  gtp->teid = htonl(teid);

  memcpy(buffer + sizeof(struct gtp_header), packet, len);
  
  // Log sebelum mengirim paket GTP-U
  LOG_I(GTPU, "Forwarding to GTP-U: %zd bytes to %s:%d, TEID: %08x\n",
    len, inet_ntoa(remote_addr->sin_addr), ntohs(remote_addr->sin_port), teid);
  
    ssize_t sent = sendto(udp_sock, buffer, sizeof(struct gtp_header) + len, 0,
                        (struct sockaddr *)remote_addr, sizeof(*remote_addr));

  if (sent < 0) {
      LOG_E(GTPU, "Error sending GTP packet: %s\n", strerror(errno));
  } else {
      LOG_I(GTPU, "Sent %zd bytes via GTP-U to %s:%d\n",
            sent, inet_ntoa(remote_addr->sin_addr), ntohs(remote_addr->sin_port));
  }
}
// Processing GTP-U packet
void process_gtpu_packet(char *buffer, ssize_t len, int tun_fd) {
  struct gtp_header *gtp = (struct gtp_header *)buffer;

  if (gtp->message_type == GTP_GPDU) {
      ssize_t written = write(tun_fd, buffer + sizeof(struct gtp_header), len - sizeof(struct gtp_header));
      if (written < 0) {
          LOG_E(GTPU, "Error writing to TUN device: %s\n", strerror(errno));
      } else {
          LOG_I(GTPU, "Wrote %zd bytes to TUN device (from GTP-U)\n", written);
      }
  } else {
      LOG_W(GTPU, "Unhandled GTP message type: %02x\n", gtp->message_type);
  }
}

void gtpu_packet_loop(int tun_fd, int udp_sock, struct sockaddr_in remote_addr) {
  fd_set read_fds;
  struct sockaddr_in sender_addr;
  socklen_t addr_len = sizeof(sender_addr);
  char buffer[BUFFER_SIZE];

  while (1) {
      FD_ZERO(&read_fds);
      FD_SET(tun_fd, &read_fds);
      FD_SET(udp_sock, &read_fds);

      int max_fd = (tun_fd > udp_sock ? tun_fd : udp_sock) + 1;
      int activity = select(max_fd, &read_fds, NULL, NULL, NULL);

      if (activity < 0 && errno != EINTR) {
          LOG_E(GTPU, "Select error: %s\n", strerror(errno));
          continue;
      }

      if (FD_ISSET(tun_fd, &read_fds)) {
          ssize_t len = read(tun_fd, buffer, BUFFER_SIZE);
          if (len < 0) {
              LOG_E(GTPU, "Error reading from TUN device: %s\n", strerror(errno));
              continue;
          }
          LOG_I(GTPU, "Received %zd bytes from TUN device\n", len);
          forward_to_gtpu(udp_sock, &remote_addr, buffer, len, 0x12345678);
      }

      if (FD_ISSET(udp_sock, &read_fds)) {
          ssize_t len = recvfrom(udp_sock, buffer, BUFFER_SIZE, 0,
                                 (struct sockaddr *)&sender_addr, &addr_len);
          if (len < 0) {
              LOG_E(GTPU, "Error receiving from UDP socket: %s\n", strerror(errno));
              continue;
          }
          LOG_I(GTPU, "Received %zd bytes from UDP socket\n", len);
          process_gtpu_packet(buffer, len, tun_fd);
      }
  }
}

int initialize_gtpu_system(const char *local_ip, const char *remote_ip) {
  LOG_I(GTPU, "Initializing GTP-U system...\n");

  // Create TUN device
  tun_fd = create_tun_device("gtp-tun0");
  if (tun_fd < 0) {
      LOG_E(GTPU, "Failed to create GTP-U TUN device\n");
      return -1;
  }

  // Bring up the interface
  int ret = system("ip link set gtp-tun0 up");
  if (ret != 0) {
      LOG_E(GTPU, "Failed to bring up gtp-tun0, return code: %d\n", ret);
      return -1;
  }

  // Create UDP socket
  udp_sock = socket(AF_INET, SOCK_DGRAM, 0);
  if (udp_sock < 0) {
      LOG_E(GTPU, "Failed to create UDP socket: %s\n", strerror(errno));
      return -1;
  }

  struct sockaddr_in local_addr = {0};
  local_addr.sin_family = AF_INET;
  local_addr.sin_port = htons(GTPU_PORT);
  inet_pton(AF_INET, local_ip, &local_addr.sin_addr);

  if (bind(udp_sock, (struct sockaddr *)&local_addr, sizeof(local_addr)) < 0) {
      LOG_E(GTPU, "Failed to bind UDP socket: %s\n", strerror(errno));
      close(udp_sock);
      return -1;
  }

  LOG_I(GTPU, "GTP-U system initialized, listening on %s:%d\n", local_ip, GTPU_PORT);
  gtpu_initialized = true;
  return 0;
}

int main() {
 if (!gtpu_initialized) {
        pthread_mutex_lock(&globGtp.gtp_lock);
        if (!gtpu_initialized) {  // Double-check setelah lock
            LOG_I(GTPU, "Initializing GTP-U system at first packet send.\n");
            if (initialize_gtpu_system("192.168.60.77", "192.168.60.88") == 0) {
                gtpu_initialized = true;
                LOG_I(GTPU, "GTP-U initialization successful.\n");
            } else {
                LOG_E(GTPU, "Failed to initialize GTP-U system.\n");
                pthread_mutex_unlock(&globGtp.gtp_lock);
                return;
            }
        }
        pthread_mutex_unlock(&globGtp.gtp_lock);
    }
}
