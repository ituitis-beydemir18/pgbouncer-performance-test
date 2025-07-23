#!/bin/bash

# Test Client Setup Script
# This script installs PostgreSQL client tools and performance test scripts

set -e

# Log all output
exec > >(tee /var/log/client-setup.log)
exec 2>&1

echo "Starting test client setup at $(date)"

# Update system
apt-get update
apt-get upgrade -y

# Install PostgreSQL client, pgbench, and other tools
apt-get install -y postgresql-client postgresql-contrib python3 python3-pip htop sysstat bc

# Install Python packages for analysis
pip3 install psycopg2-binary matplotlib pandas

# Database and PgBouncer connection details from Terraform
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
DB_PASSWORD="${db_password}"
PGBOUNCER_HOST="${pgbouncer_host}"
PGBOUNCER_PORT="${pgbouncer_port}"

echo "Configuring test client for:"
echo "  Database: $DB_HOST:$DB_PORT"
echo "  PgBouncer: $PGBOUNCER_HOST:$PGBOUNCER_PORT"

# Set environment variables
cat > /home/ubuntu/.env << EOF
export DB_HOST="$DB_HOST"
export DB_PORT="$DB_PORT"
export DB_NAME="$DB_NAME"
export DB_USERNAME="$DB_USERNAME"
export DB_PASSWORD="$DB_PASSWORD"
export PGBOUNCER_HOST="$PGBOUNCER_HOST"
export PGBOUNCER_PORT="$PGBOUNCER_PORT"
export PGPASSWORD="$DB_PASSWORD"
EOF

# Source environment in bash profile
echo "source /home/ubuntu/.env" >> /home/ubuntu/.bashrc

# Wait for PgBouncer to be ready
echo "Waiting for PgBouncer to be ready..."
for i in {1..60}; do
    if pg_isready -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT"; then
        echo "PgBouncer is ready!"
        break
    fi
    echo "Waiting for PgBouncer... attempt $i/60"
    sleep 5
done

# Test connections
echo "Testing database connections..."
export PGPASSWORD="$DB_PASSWORD"

# Test direct connection
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ Direct database connection successful"
else
    echo "✗ Direct database connection failed"
fi

# Test PgBouncer connection
if psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ PgBouncer connection successful"
else
    echo "✗ PgBouncer connection failed"
fi

# Create placeholder test script (will be replaced by post_deploy.sh)
cat > /home/ubuntu/run_performance_test.sh << 'EOF'
#!/bin/bash
source /home/ubuntu/.env

echo "Performance test script placeholder"
echo "Run post_deploy.sh to install full test scripts"
echo ""
echo "Environment configured for:"
echo "  Database: $DB_HOST:$DB_PORT"
echo "  PgBouncer: $PGBOUNCER_HOST:$PGBOUNCER_PORT"
echo ""
echo "Basic test commands:"
echo "  psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USERNAME -d \$DB_NAME -c 'SELECT version();'"
echo "  psql -h \$PGBOUNCER_HOST -p \$PGBOUNCER_PORT -U \$DB_USERNAME -d \$DB_NAME -c 'SELECT version();'"
EOF

chmod +x /home/ubuntu/run_performance_test.sh

# Set ownership of all files
chown -R ubuntu:ubuntu /home/ubuntu/

echo "Test client setup completed successfully at $(date)"
echo ""
echo "Setup complete! Ready for performance testing." 
echo "Run post_deploy.sh to install full performance test scripts." 