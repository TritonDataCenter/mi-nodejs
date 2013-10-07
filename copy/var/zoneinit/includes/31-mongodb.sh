# Get password from metadata, unless passed as MONGODB_PW, or set one.
log "getting mongodb_pw"
MONGODB_PW=${MONGODB_PW:-$(mdata-get mongodb_pw 2>/dev/null)} || \
MONGODB_PW=$(od -An -N8 -x /dev/random | head -1 | tr -d ' ');

# Get Quickbackup user and password
log "getting qb_pw"
QB_PW=$(od -An -N8 -x /dev/random | head -1 | sed 's/^[ \t]*//' | tr -d ' ');
QB_US=qb-$(zonename | awk -F\- '{ print $5 }');

# Start MongoDB
log "starting the MongoDB instance"
svcadm enable pkgsrc/mongodb

# Wait for MongoDB to start
log "waiting for the socket to show up"
COUNT="0";
while [[ ! -e /tmp/mongodb-27017.sock ]]; do
	sleep 1
	((COUNT=COUNT+1))
	if [[ ${COUNT} -eq 60 ]]; then
	  log "ERROR Could not talk to MongoDB after 60 seconds"
          ERROR=yes
          break 1
        fi
done
[[ -n "${ERROR}" ]] && exit 31
log "(it took ${COUNT} seconds to start properly)"
sleep 1

# Check if MongoDB service is online
[[ "$(svcs -Ho state pkgsrc/mongodb)" == "online" ]] || \
  ( log "ERROR MongoDB SMF not reporting as 'online'" && exit 31 )

# Configure MongoDB password
log "Setting the MongoDB admin password"
/opt/local/bin/mongo 127.0.0.1/admin --eval "db.addUser(\"admin\", \"${MONGODB_PW}\")" 2>/dev/null || \
  ( log "ERROR MongoDB set admin pass failed to execute." && exit 31 )
sleep 2;

# Configure MongoDB Quickbackup user
log "Setting the MongoDB qb password"
/opt/local/bin/mongo 127.0.0.1/admin -uadmin -p${MONGODB_PW} --eval "db.addUser(\"${QB_US}\", \"${QB_PW}\")" 2>/dev/null || \
  ( log "ERROR MongoDB set qb pass failed to execute." && exit 31 )

# Configure MongoDB authentication
log "putting auth in mongodb.conf and starting mongodb"
echo "auth = true" >> /opt/local/etc/mongodb.conf

# Configure MongoDB Quickbackup service
log "configuring quickbackup-mongodb with the proper user/pass"
svccfg -s pkgsrc/quickbackup-mongodb setprop quickbackup/username = astring: ${QB_US}
svccfg -s pkgsrc/quickbackup-mongodb setprop quickbackup/password = astring: ${QB_PW}
svcadm refresh quickbackup-mongodb

# Disable MongoDB, clear logs, enable MongoDB
log "stopping mongodb and clearing logs"
svcadm disable -s pkgsrc/mongodb
rm /var/log/mongodb/mongodb.log
touch /var/log/mongodb/mongodb.log
chown -R mongodb:mongodb /var/log/mongodb
chown -R mongodb:mongodb /var/mongodb
svcadm enable pkgsrc/mongodb
