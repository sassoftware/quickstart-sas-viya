#!/bin/bash

# add user to default openLDAP server
# execute this script from the ansible controller

##### set parms
USER=testuser
USERPW=testuserpw
ADMINPW=adminadmin

#
# add user/set pw
#
cat << EOF > /tmp/adduser.ldif
dn: uid=$USER,ou=users,dc=sasviya,dc=com
cn: $USER
givenName: New
sn: User
objectClass: top
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: posixAccount
loginShell: /bin/bash
uidNumber: 100013
gidNumber: 100001
homeDirectory: /home/$USER
mail: $USER@stateful.viya.sas
displayName: $USER User
EOF

scp /tmp/adduser.ldif stateful:/tmp/adduser.ldif
ssh stateful ldapadd    -x -h localhost -D "cn=admin,dc=sasviya,dc=com" -w $ADMINPW -f /tmp/adduser.ldif

ssh stateful ldappasswd -s $USERPW -x -w $ADMINPW -D "cn=admin,dc=sasviya,dc=com" "uid=$USER,ou=users,dc=sasviya,dc=com"

# 
# add user to sasusers group
#
cat << EOF > /tmp/addtogroup.ldif
dn: cn=sasusers,ou=groups,dc=sasviya,dc=com
changetype: modify
add: memberUid
memberUid: $USER
-
add: member
member: uid=$USER,ou=users,dc=sasviya,dc=com
EOF

scp /tmp/addtogroup.ldif stateful:/tmp/addtogropu.ldif
ssh stateful ldapadd -x -h localhost -D "cn=admin,dc=sasviya,dc=com" -w $ADMINPW -f /tmp/addtogroup.ldif


#
# add user home dir on programming  host
#
ssh prog sudo mkdir -p /home/$USER
ssh prog sudo chown $USER:sasusers /home/$USER



