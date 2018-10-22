/*
 Copyright 2018 New Vector Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXCrypto_Private.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoBackupTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}
@end

@implementation MXCryptoBackupTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;

    [super tearDown];
}

/**
 - Create a backup version on the server
 - Get the current version from the server
 - Check they match
 */
- (void)testRESTCreateKeyBackupVersion
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        // - Create a backup version on the server
        MXKeyBackupVersion *keyBackupVersion =
        [MXKeyBackupVersion modelFromJSON:@{
                                            @"algorithm": kMXCryptoMegolmBackupAlgorithm,
                                            @"auth_data": @{
                                                    @"public_key": @"abcdefg",
                                                    @"signatures": @{
                                                            @"something": @{
                                                                    @"ed25519:something": @"hijklmnop"
                                                                    }
                                                            }
                                                    }
                                            }];

        [aliceRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            // - Get the current version from the server
            [aliceRestClient keyBackupVersion:^(MXKeyBackupVersion *keyBackupVersion2) {

                // - Check they match
                XCTAssertNotNil(keyBackupVersion2);
                XCTAssertEqualObjects(keyBackupVersion2.version, version);
                XCTAssertEqualObjects(keyBackupVersion2.algorithm, keyBackupVersion.algorithm);
                XCTAssertEqualObjects(keyBackupVersion2.authData, keyBackupVersion.authData);

                [expectation fulfill];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Create a backup version on the server
 - Make a backup
 - Get the backup back
 -> Check they match
 */
- (void)testRESTBackupKeys
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        // - Create a backup version on the server
        MXKeyBackupVersion *keyBackupVersion =
        [MXKeyBackupVersion modelFromJSON:@{
                                            @"algorithm": kMXCryptoMegolmBackupAlgorithm,
                                            @"auth_data": @{
                                                    @"public_key": @"abcdefg",
                                                    @"signatures": @{
                                                            @"something": @{
                                                                    @"ed25519:something": @"hijklmnop"
                                                                    }
                                                            }
                                                    }
                                            }];

        [aliceRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            //- Make a backup
            MXKeyBackupData *keyBackupData = [MXKeyBackupData new];
            keyBackupData.firstMessageIndex = 1;
            keyBackupData.forwardedCount = 2;
            keyBackupData.verified = YES;
            keyBackupData.sessionData = @{
                                          @"key": @"value"
                                          };

            NSString *roomId = @"!aRoomId:matrix.org";
            NSString *sessionId = @"ASession";

            [aliceRestClient sendKeyBackup:keyBackupData room:roomId session:sessionId version:version success:^{

                // - Get the backup back
                [aliceRestClient keysBackup:version success:^(MXKeysBackupData *keysBackupData) {

                    // -> Check they match
                    MXKeyBackupData *keyBackupData2 = keysBackupData.rooms[roomId].sessions[sessionId];
                    XCTAssertNotNil(keyBackupData2);
                    XCTAssertEqualObjects(keyBackupData2.JSONDictionary, keyBackupData.JSONDictionary);

                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 - Create a backup version on the server
 - Make a backup
 - Delete it
 - Get the backup back
 -> Check it is now empty
 */
- (void)testRESTDeleteBackupKeys
{
    [matrixSDKTestsData doMXRestClientTestWithAlice:self readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation) {

        // - Create a backup version on the server
        MXKeyBackupVersion *keyBackupVersion =
        [MXKeyBackupVersion modelFromJSON:@{
                                            @"algorithm": kMXCryptoMegolmBackupAlgorithm,
                                            @"auth_data": @{
                                                    @"public_key": @"abcdefg",
                                                    @"signatures": @{
                                                            @"something": @{
                                                                    @"ed25519:something": @"hijklmnop"
                                                                    }
                                                            }
                                                    }
                                            }];

        [aliceRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            //- Make a backup
            MXKeyBackupData *keyBackupData = [MXKeyBackupData new];
            keyBackupData.firstMessageIndex = 1;
            keyBackupData.forwardedCount = 2;
            keyBackupData.verified = YES;
            keyBackupData.sessionData = @{
                                          @"key": @"value"
                                          };

            NSString *roomId = @"!aRoomId:matrix.org";
            NSString *sessionId = @"ASession";

            [aliceRestClient sendKeyBackup:keyBackupData room:roomId session:sessionId version:version success:^{

                // - Delete it
                [aliceRestClient deleteKeyFromBackup:roomId session:sessionId version:version success:^{

                    // - Get the backup back
                    // TODO: The test currently fails because of https://github.com/matrix-org/synapse/issues/4056
                    [aliceRestClient keysBackup:version success:^(MXKeysBackupData *keysBackupData) {

                        // -> Check it is now empty
                        XCTAssertNotNil(keysBackupData);
                        XCTAssertEqual(keysBackupData.rooms.count, 0);

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


/**
- From doE2ETestWithAliceAndBobInARoomWithCryptedMessages, we should have non backed up keys
- Check backup keys after having marked one as backuped
- Reset keys backup markers
*/
- (void)testBackupStore
{
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        // - From doE2ETestWithAliceAndBobInARoomWithCryptedMessages, we should have non backed up keys
        NSArray<MXOlmInboundGroupSession*> *sessions = [aliceSession.crypto.store inboundGroupSessionsToBackup:100];
        NSUInteger sessionsCount = sessions.count;
        XCTAssertGreaterThan(sessionsCount, 0);

        // - Check backup keys after having marked one as backuped
        MXOlmInboundGroupSession *session = sessions.firstObject;
        [aliceSession.crypto.store markBackupDoneForInboundGroupSessionWithId:session.session.sessionIdentifier andSenderKey:session.senderKey];
        sessions = [aliceSession.crypto.store inboundGroupSessionsToBackup:100];
        XCTAssertEqual(sessions.count, sessionsCount - 1);

        // - Reset keys backup markers
        [aliceSession.crypto.store resetBackupMarkers];
        sessions = [aliceSession.crypto.store inboundGroupSessionsToBackup:100];
        XCTAssertEqual(sessions.count, sessionsCount);

        [expectation fulfill];
    }];
}

@end

#pragma clang diagnostic pop
