#!/bin/bash
# Создание бекапа и обновление docker-compose

COMPOSE_LOCATION=$(which docker-compose)
BACKUP_DIR="$HOME/docker-compose-backups"
mkdir -p "$BACKUP_DIR"

# Бекап
if [ -f "$COMPOSE_LOCATION" ]; then
    BACKUP_FILE="$BACKUP_DIR/docker-compose-backup-$(date +%Y%m%d-%H%M%S)"
    sudo cp "$COMPOSE_LOCATION" "$BACKUP_FILE"
    echo "✓ Backup created: $BACKUP_FILE"
    echo "  Current version: $(docker-compose version --short 2>/dev/null || echo 'unknown')"
else
    echo "✗ docker-compose not found at $COMPOSE_LOCATION"
    exit 1
fi

# Обновление
echo "Downloading latest docker-compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o "$COMPOSE_LOCATION"
sudo chmod +x "$COMPOSE_LOCATION"

# Проверка
echo "New version:"
docker-compose version