#!/bin/bash

# PgBouncer Setup Script
# This script installs and configures PgBouncer on Ubuntu

set -e

# Log all output
exec > >(tee /var/log/pgbouncer-setup.log)
exec 2>&1

echo "Starting PgBouncer setup at $(date)"

# Update system
apt-get update
apt-get upgrade -y

# Install PgBouncer and PostgreSQL client
apt-get install -y pgbouncer postgresql-client

# Create pgbouncer user and directories
useradd -r -s /bin/false pgbouncer || true
mkdir -p /etc/pgbouncer
mkdir -p /var/log/pgbouncer
chown -R pgbouncer:pgbouncer /var/log/pgbouncer

# Database connection details from Terraform
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
DB_PASSWORD="${db_password}"

echo "Configuring PgBouncer for database at $DB_HOST:$DB_PORT"

# Create PgBouncer configuration
cat > /etc/pgbouncer/pgbouncer.ini << EOF
;; PgBouncer Configuration for Performance Testing

;; Database connections
[databases]
$DB_NAME = host=$DB_HOST port=$DB_PORT dbname=$DB_NAME

;; PgBouncer settings
[pgbouncer]

;;; Administrative settings
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
listen_addr = 0.0.0.0
listen_port = 6432
unix_socket_dir = /var/run/postgresql
auth_file = /etc/pgbouncer/userlist.txt
auth_type = md5

;;; Pool settings - optimized for performance testing
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 100
min_pool_size = 25
reserve_pool_size = 25
reserve_pool_timeout = 5
max_db_connections = 100
max_user_connections = 1000

;;; Connection settings
server_reset_query = DISCARD ALL
server_check_delay = 30
server_check_query = select 1
server_lifetime = 3600
server_idle_timeout = 600

;;; Client settings
client_idle_timeout = 0
client_login_timeout = 60

;;; Logging
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60

;;; Performance settings
ignore_startup_parameters = extra_float_digits

;;; Safety settings
application_name_add_host = 1
conffile = /etc/pgbouncer/pgbouncer.ini
EOF

# Create userlist.txt with hashed password
echo "Creating user authentication file..."

# Generate MD5 hash for password (md5 + username + password)
MD5_HASH=$(echo -n "$DB_PASSWORD$DB_USERNAME" | md5sum | cut -d' ' -f1)
FULL_HASH="md5$MD5_HASH"

cat > /etc/pgbouncer/userlist.txt << EOF
"$DB_USERNAME" "$FULL_HASH"
EOF

# Set proper permissions
chown -R pgbouncer:pgbouncer /etc/pgbouncer
chmod 640 /etc/pgbouncer/pgbouncer.ini
chmod 640 /etc/pgbouncer/userlist.txt

# Create systemd service
cat > /etc/systemd/system/pgbouncer.service << EOF
[Unit]
Description=PgBouncer PostgreSQL connection pooler
Documentation=man:pgbouncer(1)
After=network.target

[Service]
Type=forking
User=pgbouncer
Group=pgbouncer
ExecStart=/usr/bin/pgbouncer -d /etc/pgbouncer/pgbouncer.ini
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/postgresql/pgbouncer.pid
LimitNOFILE=65536

# Restart policy
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Create directory for PID file
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql

# Test database connectivity before starting PgBouncer
echo "Testing database connectivity..."
export PGPASSWORD="$DB_PASSWORD"

# Wait for RDS to be available
echo "Waiting for database to be available..."
for i in {1..30}; do
    if pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME"; then
        echo "Database is ready!"
        break
    fi
    echo "Waiting for database... attempt $i/30"
    sleep 10
done

# Test connection
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
    echo "Successfully connected to PostgreSQL database"
else
    echo "Failed to connect to PostgreSQL database"
    exit 1
fi

# Create test table and data for benchmarking
echo "Setting up test data..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" << 'EOSQL'
-- Create pgbench tables if they don't exist
\c testdb

-- Create the standard pgbench schema
CREATE TABLE IF NOT EXISTS pgbench_accounts (
    aid    INTEGER NOT NULL,
    bid    INTEGER,
    abalance INTEGER,
    filler CHAR(84)
);

CREATE TABLE IF NOT EXISTS pgbench_branches (
    bid     INTEGER NOT NULL,
    bbalance INTEGER,
    filler  CHAR(88)
);

CREATE TABLE IF NOT EXISTS pgbench_history (
    tid    INTEGER,
    bid    INTEGER,
    aid    INTEGER,
    delta  INTEGER,
    mtime  TIMESTAMP,
    filler CHAR(22)
);

CREATE TABLE IF NOT EXISTS pgbench_tellers (
    tid    INTEGER NOT NULL,
    bid    INTEGER,
    tbalance INTEGER,
    filler CHAR(84)
);

-- Insert some sample data for testing
INSERT INTO pgbench_branches (bid, bbalance, filler) 
SELECT generate_series(1, 10), 0, 'filler' 
ON CONFLICT DO NOTHING;

INSERT INTO pgbench_tellers (tid, bid, tbalance, filler) 
SELECT generate_series(1, 100), (generate_series(1, 100) - 1) % 10 + 1, 0, 'filler' 
ON CONFLICT DO NOTHING;

INSERT INTO pgbench_accounts (aid, bid, abalance, filler) 
SELECT generate_series(1, 10000), (generate_series(1, 10000) - 1) % 10 + 1, 0, 'filler' 
ON CONFLICT DO NOTHING;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS pgbench_accounts_pkey ON pgbench_accounts (aid);
CREATE INDEX IF NOT EXISTS pgbench_branches_pkey ON pgbench_branches (bid);
CREATE INDEX IF NOT EXISTS pgbench_tellers_pkey ON pgbench_tellers (tid);

EOSQL

# Enable and start PgBouncer
systemctl daemon-reload
systemctl enable pgbouncer
systemctl start pgbouncer

# Check if PgBouncer started successfully
sleep 5
if systemctl is-active --quiet pgbouncer; then
    echo "PgBouncer started successfully"
    
    # Test PgBouncer connection
    if psql -h localhost -p 6432 -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
        echo "Successfully connected through PgBouncer"
    else
        echo "Failed to connect through PgBouncer"
        systemctl status pgbouncer
        journalctl -u pgbouncer -n 20
    fi
else
    echo "Failed to start PgBouncer"
    systemctl status pgbouncer
    journalctl -u pgbouncer -n 20
    exit 1
fi

# Set up monitoring script
cat > /home/ubuntu/monitor_pgbouncer.sh << 'EOF'
#!/bin/bash
echo "=== PgBouncer Status ==="
systemctl status pgbouncer --no-pager

echo -e "\n=== PgBouncer Pool Status ==="
PGPASSWORD="$DB_PASSWORD" psql -h localhost -p 6432 -U "$DB_USERNAME" -d pgbouncer -c "SHOW POOLS;"

echo -e "\n=== PgBouncer Stats ==="
PGPASSWORD="$DB_PASSWORD" psql -h localhost -p 6432 -U "$DB_USERNAME" -d pgbouncer -c "SHOW STATS;"

echo -e "\n=== Active Connections ==="
PGPASSWORD="$DB_PASSWORD" psql -h localhost -p 6432 -U "$DB_USERNAME" -d pgbouncer -c "SHOW CLIENTS;"
EOF

chmod +x /home/ubuntu/monitor_pgbouncer.sh
chown ubuntu:ubuntu /home/ubuntu/monitor_pgbouncer.sh

# Create connection test script
cat > /home/ubuntu/test_connections.sh << EOF
#!/bin/bash

echo "Testing Direct PostgreSQL Connection..."
export PGPASSWORD="$DB_PASSWORD"
time psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;"

echo -e "\nTesting PgBouncer Connection..."
time psql -h localhost -p 6432 -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;"

echo -e "\nConnection test completed."
EOF

chmod +x /home/ubuntu/test_connections.sh
chown ubuntu:ubuntu /home/ubuntu/test_connections.sh

echo "PgBouncer setup completed successfully at $(date)"
echo "You can monitor PgBouncer with: ./monitor_pgbouncer.sh"
echo "You can test connections with: ./test_connections.sh" 