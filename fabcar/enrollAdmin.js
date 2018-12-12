'use strict';
/*
* Copyright IBM Corp All Rights Reserved
*
* SPDX-License-Identifier: Apache-2.0
*/
/*
 * Enroll the admin user
 */

var Fabric_Client = require('fabric-client');
var Fabric_CA_Client = require('fabric-ca-client');

var path = require('path');
var util = require('util');
var os = require('os');

var fabric_client = new Fabric_Client();

async function doEnrollAdmin(crypto_suite) {
    var tlsOptions = {
        trustedRoots: [],
        verify: false
    };
    // be sure to change the http to https when the CA is running TLS enabled
    // 注意: http/https: 由 docker-compose 中的 FABRIC_CA_SERVER_TLS_ENABLED 决定.
    //      caName: 由 docker-compose 中的 FABRIC_CA_SERVER_CA_NAME 决定
    var fabric_ca_client = new Fabric_CA_Client('https://47.104.201.221:7054', tlsOptions, 'ca-org1', crypto_suite);
    try {
        var enrollment = await fabric_ca_client.enroll({
            enrollmentID: 'admin',
            enrollmentSecret: 'adminpw'     // 必须和 ../basic-network/docker-compose.yml 里的ca配置的相同
        });
        console.log('Successfully enrolled admin user "admin"');
        var user = await fabric_client.createUser({
            username: 'admin',
            mspid: 'Org1MSP',
            cryptoContent: {
                privateKeyPEM: enrollment.key.toBytes(),
                signedCertPEM: enrollment.certificate
            }
        });
        await fabric_client.setUserContext(user);
        return user;
    } catch (err) {
        console.error('Failed to enroll and persist admin. Error: ' + err.stack ? err.stack : err);
        throw new Error('Failed to enroll admin');
    }
}

async function enrollAdmin() {
    var store_path = path.join(__dirname, 'hfc-key-store');
    console.log(' Store path:' + store_path);
    var admin_user;
    try {
        // create the key value store as defined in the fabric-client/config/default.json 'key-value-store' setting
        var state_store = await Fabric_Client.newDefaultKeyValueStore({
            path: store_path
        });
        // assign the store to the fabric client
        fabric_client.setStateStore(state_store);
        var crypto_suite = Fabric_Client.newCryptoSuite();
        // use the same location for the state store (where the users' certificate are kept)
        // and the crypto store (where the users' keys are kept)
        var crypto_store = Fabric_Client.newCryptoKeyStore({
            path: store_path
        });
        crypto_suite.setCryptoKeyStore(crypto_store);
        fabric_client.setCryptoSuite(crypto_suite);
        // first check to see if the admin is already enrolled
        var user_from_store = await fabric_client.getUserContext('admin', true);
        if (user_from_store && user_from_store.isEnrolled()) {
            console.log('Successfully loaded admin from persistence');
            admin_user = user_from_store;
        } else {
            // need to enroll it with CA server
            admin_user = await doEnrollAdmin(crypto_suite);
        }
        console.log('Assigned the admin user to the fabric client ::' + admin_user.toString());
    } catch (err) {
        console.error('Failed to enroll admin: ' + err);
    }
}

enrollAdmin();
