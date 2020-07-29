'use strict';

/**
 * Module dependencies
 */

/* eslint-disable no-unused-vars */
// Public node modules.
const _ = require('lodash');
const AWS = require('aws-sdk');

AWS.CredentialProviderChain.defaultProviders = [
    function () {
        return new AWS.EnvironmentCredentials('AWS');
    },
    function () {
        return new AWS.EnvironmentCredentials('AMAZON');
    },
    function () {
        return new AWS.SharedIniFileCredentials();
    },
    function () {
        return new AWS.ECSCredentials();
    },
    function () {
        return new AWS.ProcessCredentials();
    },
    function () {
        return new AWS.TokenFileWebIdentityCredentials();
    },
    function () {
        return new AWS.EC2MetadataCredentials()
    }
]

module.exports = {
    init(config) {
        const S3 = new AWS.S3({
            apiVersion: '2006-03-01',
            ...config,
        });

        return {
            upload(file, customParams = {}) {
                return new Promise((resolve, reject) => {
                    // upload file on S3 bucket
                    const path = file.path ? `${file.path}/` : '';
                    let key = `${path}${file.hash}${file.ext}`;
                    S3.upload(
                            {
                                Key: key,
                                Body: Buffer.from(file.buffer, 'binary'),
                                ContentType: file.mime,
                                ...customParams,
                            },
                            (err, data) => {
                                if (err) {
                                    return reject(err);
                                }

                                // set the bucket file url
                                // file.url = data.Location;
                                file.url = `https://${config.mediasCloudfrontUrl}/${key}`

                                resolve();
                            }
                    );
                });
            },
            delete(file, customParams = {}) {
                return new Promise((resolve, reject) => {
                    // delete file on S3 bucket
                    const path = file.path ? `${file.path}/` : '';
                    S3.deleteObject(
                            {
                                Key: `${path}${file.hash}${file.ext}`,
                                ...customParams,
                            },
                            (err, data) => {
                                if (err) {
                                    return reject(err);
                                }

                                resolve();
                            }
                    );
                });
            },
        };
    },
};