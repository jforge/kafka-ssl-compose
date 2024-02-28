#!/bin/bash
STORE_PASS=awesomekafka
KEY_PASS=awesomekafka

set -o nounset \
    -o errexit

printf "Deleting previous (if any)..."
rm -rf secrets
mkdir secrets
mkdir -p tmp
echo " OK!"
# Generate CA key
printf "Creating CA..."
openssl req -new -x509 -keyout tmp/datahub-ca.key -out tmp/datahub-ca.crt -days 365 -subj '/CN=io.cybus/OU=test/O=cybus/L=hamburg/C=de' -passin pass:$KEY_PASS -passout pass:$KEY_PASS >/dev/null 2>&1

echo " OK!"

shopt -s expand_aliases
alias keytool="docker run --rm -it -v $(pwd)/secrets:/secrets -v $(pwd)/tmp:/tmp amazoncorretto:8-alpine-jdk keytool"

set -x
for i in 'broker' 'producer' 'consumer' 'schema-registry'
do
	printf "Creating cert and keystore of $i..."
	# Create keystores
	keytool -genkey -noprompt \
				 -alias $i \
				 -dname "CN=$i, OU=test, O=cybus, L=hamburg, C=de" \
				 -keystore /secrets/$i.keystore.jks \
				 -keyalg RSA \
				 -storepass $STORE_PASS \
				 -keypass $KEY_PASS  >/dev/null 2>&1

	# Create CSR, sign the key and import back into keystore
	keytool -keystore /secrets/$i.keystore.jks -alias $i -certreq -file tmp/$i.csr -storepass $STORE_PASS -keypass $KEY_PASS >/dev/null 2>&1

	openssl x509 -req -CA tmp/datahub-ca.crt -CAkey tmp/datahub-ca.key -in tmp/$i.csr -out tmp/$i-ca-signed.crt -days 365 -CAcreateserial -passin pass:$STORE_PASS  >/dev/null 2>&1

	keytool -keystore /secrets/$i.keystore.jks -alias CARoot -import -noprompt -file tmp/datahub-ca.crt -storepass $STORE_PASS -keypass $KEY_PASS >/dev/null 2>&1

	keytool -keystore /secrets/$i.keystore.jks -alias $i -import -file tmp/$i-ca-signed.crt -storepass $STORE_PASS -keypass $KEY_PASS >/dev/null 2>&1

	# Convert keystore to pkscs12
	keytool -srcstorepass $STORE_PASS -importkeystore -srckeystore secrets/$i.keystore.jks -destkeystore secrets/$i.keystore.jks -deststoretype pkcs12 -deststorepass $STORE_PASS 2>&1

	# Create truststore and import the CA cert.
	keytool -keystore /secrets/$i.truststore.jks -alias CARoot -import -noprompt -file tmp/datahub-ca.crt -storepass $STORE_PASS -keypass $KEY_PASS >/dev/null 2>&1

	# Convert truststore to pkscs12
	keytool -srcstorepass $STORE_PASS -importkeystore -srckeystore secrets/$i.truststore.jks -destkeystore secrets/$i.truststore.jks -deststoretype pkcs12 -deststorepass $STORE_PASS 2>&1
  echo " OK!"
done

echo "$STORE_PASS" > secrets/cert_creds
#rm -rf tmp

echo "SUCCEEDED"
