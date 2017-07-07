#
# Setup openldap.
#

#
# Before executing this script, install openldap using following commands.
# yum -y install openldap
# yum -y install openldap-servers
# yum -y install openldap-clients
#

###########
# Change below.
###########
DOMAIN=dc=example,dc=com
MANAGER_DN=cn=manager,${DOMAIN}
###########


#
# You don't normaly need to modify lines below.
#

read -sp "Type manager's new password." MANAGER_PASSWORD
MANAGER_PASSWORD_HASHED=$(slappasswd -s ${MANAGER_PASSWORD})


# Copy default DB configuration.
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG 
chown ldap.ldap /var/lib/ldap/DB_CONFIG 

# Start slapd and enable the service so that it will be started on each boot.
systemctl start slapd
systemctl enable slapd

# Enable 'memberof' module.
ldapadd -H ldapi:/// <<EOF
dn: cn=module,cn=config
cn: module
objectclass: olcModuleList
objectclass: top
olcmoduleload: memberof.la
olcmodulepath: /usr/lib64/openldap

dn: olcOverlay={0}memberof,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof

dn: cn=module,cn=config
cn: module
objectclass: olcModuleList
objectclass: top
olcmoduleload: refint.la
olcmodulepath: /usr/lib64/openldap

dn: olcOverlay={1}refint,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
objectClass: top
olcOverlay: {1}refint
olcRefintAttribute: memberof member manager owner
EOF


# Import schema
for i in /etc/openldap/schema/*.ldif
do
    ldapadd -Y EXTERNAL -H ldapi:/// -f $i
done

# Change domain suffix
ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: ${DOMAIN}
EOF

# Change manager dn and its password.
ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: ${MANAGER_DN}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${MANAGER_PASSWORD_HASHED}
EOF

# Set default access control rule.
ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to attrs=userPassword,shadowLastChange
  by dn=${MANAGER_DN} write
  by anonymous auth
  by self write
  by * none
olcAccess: {1}to dn.base=""
  by * read
olcAccess: {2}to *
  by dn=${MANAGER_DN} write
  by * read
EOF

# Populate DIT with minimul objects.
ldapadd -x -D ${MANAGER_DN} -w ${MANAGER_PASSWORD} <<EOF
dn: ${DOMAIN}
objectClass: top
objectClass: dcObject
objectclass: organization
o: $(echo ${DOMAIN}|sed -e 's/dc=\([^,]*\),.*/\1/')
dc: $(echo ${DOMAIN}|sed -e 's/dc=\([^,]*\),.*/\1/')

dn: ${MANAGER_DN}
objectClass: organizationalRole
cn: $(echo ${MANAGER_DN}|sed -e 's/cn=\([^,]*\),.*/\1/')

dn: ou=People,dc=example,dc=com
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=example,dc=com
objectClass: groupOfNames
cn: Group
member: ${MANAGER_DN}
EOF

