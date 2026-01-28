# TYPO3 Base Prod Container for PHP 8.4

This environment provides a pre-configured **PHP 8.4** container. Thanks to **fixuid**, all file permissions are automatically mapped to your local host user to prevent `root` permission conflicts.

---

## 1. Repository Structure & Container Variations
The repository is designed modularly to cover different use cases:

* **Base Image:** The `Dockerfile` in the root directory serves as the fundamental base image. It contains the core configuration for PHP 8.4 and all system dependencies required for TYPO3.
* **Variations:** In the `/containers` directory, you will find specialized extensions building upon the base image (e.g., the **Dev Container** including Xdebug and Composer).
## 2. Preparation
To ensure the container adopts your file permissions correctly, the system needs to know your local **UID** (User ID) and **GID** (Group ID). Create a `.env` file in your project root:

```bash
UID=$(id -u)
GID=$(id -g)
```
## 3. Starting the Environment
   The image is pulled directly from the registry. A local build is generally not required:

```bash
docker compose pull
docker compose up -d
```

## 4. Working inside the Container (Composer & Shell)
   To ensure that newly created files (such as the vendor folder) do not belong to the root user, commands must be explicitly executed as www-data. While the image is pre-configured, using the explicit flag guarantees correct ownership:

    - Open an interactive shell:
        ```bash
         docker compose exec --user www-data php bash
        ```

    - Run Composer directly:
        ```bash
         docker compose exec --user www-data php composer install
        ```

> Important: Never execute commands without the --user www-data flag. If files on your host ever end up belonging to root (recognizable by lock icons or permission errors), fix them on your host system using: `sudo chown -R $(id -u):$(id -g)` .

## 5. Debugging with Xdebug
Xdebug is pre-installed but disabled by default to maintain performance.

1. Activation: Set the environment variable XDEBUG_MODE=debug in your docker-compose.yaml (or your local override).
2. IDE Connection: Your IDE (PhpStorm/VS Code) must be listening on port 9003. 
3. Host Connection: The container communicates with your machine via host.docker.internal. Ensure that the mapping from /var/www/html to your local project path is correctly configured in your IDE.

## 6. Troubleshooting & Logs
All errors (PHP runtime & FPM process) are output directly to the Docker log stream:

- View live logs:
    ```bash
     docker compose logs -f php
    ```
- Test PHP configuration:
    ```bash
     docker compose exec --user www-data php php-fpm -t
    ```

## License
This container image is provided as-is, without any warranties or guarantees of any kind.
It may be used, modified, and extended for private and commercial purposes.

Redistribution of modified or unmodified versions is permitted, provided that this notice remains included and the original authorship is clearly acknowledged.

The authors shall not be held liable for any damages, data loss, or security issues arising from the use of this container image.

## About us

MCEikens is a technology-focused company specializing in modern web solutions, containerized infrastructures, and scalable application architectures. With a strong emphasis on performance, security, and maintainability, we design and build robust systems tailored to real-world production requirements.

Our work combines practical engineering expertise with a clear focus on clean, efficient, and future-proof solutions. From containerized TYPO3 environments to custom DevOps workflows, MCEikens delivers reliable foundations for sustainable digital platforms.

### Contact
E-Mail: dialog@mceikens.de