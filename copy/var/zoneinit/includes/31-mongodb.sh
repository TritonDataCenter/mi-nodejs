# Get MongoDB password or set one.
log "getting mongodb_pw"
MONGODB_PW=$(mdata-get mongodb_pw 2>/dev/null) || MONGODB_PW=$(od -An -N8 -x /dev/random | head -1 | tr -d ' ');

# Generate quickbackup-mongodb passowrd
# (svccfg doesn't accept special characters).
log "getting qb_pw"
QB_PW=$(od -An -N8 -x /dev/random | head -1 | tr -d ' ');
QB_US=qb-$(zonename | awk -F\- '{ print $5 }');

log "starting the MongoDB instance"
svcadm enable mongodb

log "waiting for the socket to show up"
while [[ ! -e /tmp/mongodb-27017.sock ]]; do
	: ${MYCOUNT:=0}
	sleep 1
	((MYCOUNT=MYCOUNT+1))
	if [[ $MYCOUNT -eq 30 ]]; then
	  log "ERROR Could not talk to MongoDB after 30 seconds"
          ERROR=yes
          break 1
        fi
done
[[ -n "${ERROR}" ]] && exit 31
log "(it took ${MYCOUNT} seconds to start properly)"

sleep 1;

[[ "$(svcs -Ho state mongodb:default)" == "online" ]] || \
  ( log "ERROR MongoDB SMF not reporting as 'online'" && exit 31 )

log "Setting the MongoDB admin password"
mongo 127.0.0.1/admin --eval "db.addUser(\"admin\", \"${MONGODB_PW}\")" 2>/dev/null || \
  ( log "ERROR MongoDB set admin pass failed to execute." && exit 31 )

sleep 1;

log "Setting the MongoDB qb password"
mongo 127.0.0.1/admin -uadmin -p${MONGODB_PW} --eval "db.addUser(\"${QB_US}\", \"${QB_PW}\")" 2>/dev/null || \
  ( log "ERROR MongoDB set qb pass failed to execute." && exit 31 )

log "putting auth in mongodb.conf and starting mongodb"
echo "auth = true" >> /opt/local/etc/mongodb.conf

log "configuring quickbackup-mongodb with the proper user/pass"
svccfg -s quickbackup-mongodb setprop quickbackup/username = astring: ${QB_US}
svccfg -s quickbackup-mongodb setprop quickbackup/password = astring: ${QB_PW}
svcadm refresh quickbackup-mongodb

log "clearing mongodb logs"
svcadm disable mongodb:default
rm /var/log/mongodb/mongodb.log
touch /var/log/mongodb/mongodb.log
chown -R mongodb:mongodb /var/log/mongodb
chown -R mongodb:mongodb /var/mongodb
svcadm enable mongodb:default
