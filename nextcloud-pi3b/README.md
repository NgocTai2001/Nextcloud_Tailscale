# Nextcloud trên Raspberry Pi 3B với Docker Compose và Tailscale

Project này triển khai Nextcloud Server trên Raspberry Pi 3B, dùng MariaDB làm database, Redis làm cache và Tailscale để truy cập từ xa không cần mở port router.

## Cấu trúc project

```text
nextcloud-pi3b/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── scripts/
│   ├── install-docker.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── update.sh
│   ├── backup.sh
│   └── restore.sh
├── tailscale/
│   └── setup-tailscale.sh
├── data/
│   ├── nextcloud/
│   ├── db/
│   └── redis/
└── backups/
```

`data/nextcloud` chứa dữ liệu người dùng, cấu hình, custom apps và themes của Nextcloud. Mã nguồn ứng dụng Nextcloud nằm trong container image để giảm số file phải ghi ra host và giúp update gọn hơn. `data/db` chứa database MariaDB. `data/redis` chứa dữ liệu Redis nếu Redis cần ghi xuống đĩa. Thư mục `backups` chứa các file backup tạo bởi script.

## 1. Chuẩn bị Raspberry Pi

Yêu cầu:

- Raspberry Pi 3B.
- Raspberry Pi OS Lite 64-bit.
- Thẻ nhớ tốt, tối thiểu 32 GB.
- Kết nối LAN hoặc Wi-Fi ổn định.
- User có quyền `sudo`.

Khuyến nghị cho Pi 3B RAM thấp:

```bash
sudo apt-get update
sudo apt-get upgrade -y
sudo raspi-config
```

Trong `raspi-config`, bật SSH nếu bạn quản trị từ máy khác. Nếu Pi thường xuyên thiếu RAM, có thể tăng swap lên 1-2 GB, nhưng lưu ý swap nhiều sẽ làm thẻ nhớ mòn nhanh hơn.

## 2. Cài Docker và Docker Compose

Copy project này lên Raspberry Pi, sau đó chạy:

```bash
cd nextcloud-pi3b
bash scripts/install-docker.sh
```

Script sẽ:

- Update hệ thống.
- Cài Docker Engine.
- Cài Docker Compose plugin.
- Thêm user hiện tại vào group `docker`.
- In version Docker và Docker Compose.

Sau khi cài xong, reboot để quyền group `docker` có hiệu lực:

```bash
sudo reboot
```

Sau khi reboot:

```bash
cd nextcloud-pi3b
docker version
docker compose version
```

## 3. Cấu hình `.env`

Bạn có thể để script `start.sh` tự tạo `.env` từ `.env.example` và sinh mật khẩu ngẫu nhiên:

```bash
bash scripts/start.sh
```

Hoặc tự tạo và chỉnh sửa trước:

```bash
cp .env.example .env
nano .env
```

Các biến quan trọng:

```env
MYSQL_ROOT_PASSWORD=mat-khau-root-db
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=mat-khau-user-db
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=mat-khau-admin-nextcloud
NEXTCLOUD_TRUSTED_DOMAINS=192.168.1.50 100.x.y.z nextcloud-pi.your-tailnet.ts.net localhost 127.0.0.1
NEXTCLOUD_HTTP_PORT=8080
TZ=Asia/Bangkok
```

`NEXTCLOUD_TRUSTED_DOMAINS` là danh sách domain hoặc IP được Nextcloud tin cậy, cách nhau bằng dấu cách. Hãy thêm IP LAN của Pi, Tailscale IP và MagicDNS domain nếu dùng.

Lấy IP LAN:

```bash
hostname -I
```

## 4. Chạy Nextcloud

Chạy stack:

```bash
bash scripts/start.sh
```

Script sẽ tạo các thư mục dữ liệu nếu chưa có và chạy:

```bash
docker compose up -d
```

Xem trạng thái:

```bash
docker compose ps
```

Xem log:

```bash
docker compose logs -f nextcloud
docker compose logs -f mariadb
```

Truy cập nội bộ:

```text
http://<IP-LAN>:8080
```

Ví dụ:

```text
http://192.168.1.50:8080
```

Lần khởi động đầu tiên trên Raspberry Pi 3B có thể mất vài phút.

## 5. Cài Tailscale

Chạy:

```bash
bash tailscale/setup-tailscale.sh
```

Script sẽ cài Tailscale, chạy `tailscale up` và in ra Tailscale IPv4.

Bạn cũng có thể xem lại IP bằng:

```bash
tailscale ip -4
tailscale status
```

Truy cập từ xa qua Tailscale:

```text
http://<TAILSCALE-IP>:8080
```

Ví dụ:

```text
http://100.64.12.34:8080
```

Tailscale không yêu cầu mở port trên router. Máy client chỉ cần đăng nhập cùng tailnet.

## 6. Cấu hình trusted domains

Nếu bạn thêm IP hoặc MagicDNS trước lần chạy đầu tiên, chỉ cần sửa `.env`:

```env
NEXTCLOUD_TRUSTED_DOMAINS=192.168.1.50 100.64.12.34 nextcloud-pi.tailnet-name.ts.net localhost 127.0.0.1
```

Nếu Nextcloud đã được cài xong rồi, thêm trusted domain bằng `occ`:

```bash
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value=192.168.1.50
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value=100.64.12.34
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 3 --value=nextcloud-pi.tailnet-name.ts.net
```

Kiểm tra cấu hình hiện tại:

```bash
docker compose exec -u www-data nextcloud php occ config:system:get trusted_domains
```

## 7. Dừng stack

```bash
bash scripts/stop.sh
```

Lệnh này chạy:

```bash
docker compose down
```

Dữ liệu trong `data/` vẫn được giữ lại.

## 8. Backup

Tạo backup:

```bash
bash scripts/backup.sh
```

Script sẽ:

- Bật maintenance mode nếu có thể.
- Dump database MariaDB.
- Nén thư mục `data/nextcloud` trên host, gồm data, config, custom apps và themes.
- Nén thành file `.tar.gz` trong `backups/`.
- Tắt maintenance mode khi kết thúc.

File backup có dạng:

```text
backups/nextcloud-pi3b-YYYYmmdd-HHMMSS.tar.gz
```

Lưu ý: `.env` không được đưa vào file backup để tránh lộ mật khẩu. Hãy lưu `.env` ở nơi an toàn nếu cần khôi phục sang máy khác.

## 9. Restore

Đảm bảo file `.env` hiện tại khớp với database/user bạn muốn dùng, sau đó chạy:

```bash
bash scripts/restore.sh backups/nextcloud-pi3b-YYYYmmdd-HHMMSS.tar.gz
```

Script sẽ cảnh báo trước khi ghi đè. Bạn phải gõ chính xác:

```text
RESTORE
```

Quá trình restore sẽ:

- Dừng container Nextcloud.
- Khởi động MariaDB và Redis.
- Ghi đè `data/nextcloud`.
- Drop và tạo lại database Nextcloud.
- Import lại database từ backup.
- Khởi động full stack.
- Tắt maintenance mode và scan file.

## 10. Update

Cập nhật image và chạy upgrade Nextcloud:

```bash
bash scripts/update.sh
```

Khuyến nghị backup trước khi update:

```bash
bash scripts/backup.sh
bash scripts/update.sh
```

Sau update, kiểm tra:

```bash
docker compose ps
docker compose logs --tail=100 nextcloud
```

## 11. Troubleshooting

### Lỗi `permission denied` khi chạy Docker

Bạn chưa reboot hoặc chưa đăng nhập lại sau khi thêm user vào group `docker`.

```bash
sudo reboot
```

Kiểm tra:

```bash
groups
```

User hiện tại phải có group `docker`.

### Lỗi `Access through untrusted domain`

Thêm IP hoặc domain vào trusted domains:

```bash
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value=<IP-HOAC-DOMAIN>
```

Sau đó refresh trình duyệt.

### Không vào được bằng Tailscale IP

Kiểm tra Tailscale:

```bash
tailscale status
tailscale ip -4
```

Kiểm tra container có expose port:

```bash
docker compose ps
```

URL phải có port `8080`:
URL mặc định dùng port `8080`:

```text
http://<TAILSCALE-IP>:8080
```

### Port 8080 đã được dùng

Sửa trong `.env`:

```env
NEXTCLOUD_HTTP_PORT=8081
```

Sau đó chạy lại:

```bash
docker compose up -d
```

### MariaDB khởi động chậm hoặc không healthy

Xem log:

```bash
docker compose logs -f mariadb
```

Pi 3B và thẻ nhớ chậm có thể cần thêm thời gian ở lần chạy đầu tiên. Đảm bảo còn dung lượng:

```bash
df -h
```

### Nextcloud chậm hoặc Pi bị thiếu RAM

Pi 3B chỉ có 1 GB RAM, nên hãy:

- Không cài quá nhiều app Nextcloud.
- Tránh upload nhiều file lớn cùng lúc.
- Dùng thẻ nhớ hoặc SSD USB chất lượng tốt.
- Cân nhắc tăng swap.
- Chạy backup/update khi ít người dùng truy cập.

### Quên mật khẩu admin Nextcloud

Reset bằng `occ`:

```bash
docker compose exec -u www-data nextcloud php occ user:resetpassword admin
```

Thay `admin` bằng user admin của bạn nếu đã đổi trong `.env`.

## Ghi chú bảo mật

- Không commit file `.env` thật lên git public.
- Không mở port Nextcloud trực tiếp ra Internet nếu không có reverse proxy HTTPS và hardening đầy đủ.
- Với Tailscale, chỉ thiết bị trong tailnet mới truy cập được.
- Backup nên được copy ra máy khác hoặc ổ lưu trữ khác.
