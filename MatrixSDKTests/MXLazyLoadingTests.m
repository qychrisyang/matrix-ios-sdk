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
#import "MXSDKOptions.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXLazyLoadingTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXLazyLoadingTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    [super tearDown];

    matrixSDKTestsData = nil;
}

/**
Common initial conditions:
 - Alice, Bob in a room
 - Charlie joins the room
 - Dave is invited
 - Alice sends 50 messages
 - Bob sends one message
 - Alice sends 50 messages
 - Alice makes an initial /sync with lazy-loading enabled or not
*/
- (void)createScenarioWithLazyLoading:(BOOL)lazyLoading
                          readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    [self createScenarioWithLazyLoading:lazyLoading inARoomWithName:YES readyToTest:readyToTest];
}

- (void)createScenarioWithLazyLoading:(BOOL)lazyLoading
                      inARoomWithName:(BOOL)inARoomWithName
                          readyToTest:(void (^)(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString* roomId, XCTestExpectation *expectation))readyToTest
{
    // - Alice, Bob in a room
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];

        if (inARoomWithName)
        {
            // Set a room name to prevent the HS from sending us heroes through the summary API.
            // When the HS sends heroes, it also sends m.room.membership events for them. This breaks
            // how this tests suite was written.
            [roomFromBobPOV setName:@"A name" success:nil failure:nil];
        }

        [roomFromBobPOV setJoinRule:kMXRoomJoinRulePublic success:^{

            // - Charlie joins the room
            [matrixSDKTestsData doMXSessionTestWithAUser:nil readyToTest:^(MXSession *charlieSession, XCTestExpectation *expectation2) {
                [charlieSession joinRoom:roomId success:^(MXRoom *room) {

                    // - Dave is invited
                    [roomFromBobPOV inviteUser:@"@dave:localhost:8480" success:^{

                        //  - Alice sends 50 messages
                        [matrixSDKTestsData for:aliceRestClient andRoom:roomId sendMessages:50 success:^{

                            // - Bob sends a message
                            [roomFromBobPOV sendTextMessage:@"I am Bob" success:^(NSString *eventId) {

                                // - Alice sends 50 messages
                                [matrixSDKTestsData for:aliceRestClient andRoom:roomId sendMessages:50 success:^{

                                    // - Alice makes an initial /sync
                                    MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
                                    [matrixSDKTestsData retain:aliceSession];


                                    // Alice makes an initial /sync with lazy-loading enabled or not
                                    MXFilterJSONModel *filter;
                                    if (lazyLoading)
                                    {
                                        filter = [MXFilterJSONModel syncFilterForLazyLoading];
                                    }

                                    [aliceSession startWithSyncFilter:filter onServerSyncDone:^{

                                        // We are done
                                        readyToTest(aliceSession, bobSession, charlieSession, roomId, expectation);

                                    } failure:^(NSError *error) {
                                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                        [expectation fulfill];
                                    }];
                                }];
                            } failure:^(NSError *error) {
                                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                [expectation fulfill];
                            }];
                        }];

                    } failure:^(NSError *error) {
                        XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}


- (void)testLazyLoadingFilterSupportHSSide
{
    [matrixSDKTestsData doMXRestClientTestWithBob:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        MXFilterJSONModel *lazyLoadingFilter = [MXFilterJSONModel syncFilterForLazyLoading];

        [mxSession startWithSyncFilter:lazyLoadingFilter onServerSyncDone:^{

            XCTAssertNotNil(mxSession.syncFilterId);
            XCTAssertTrue(mxSession.syncWithLazyLoadOfRoomMembers);

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


// After the test scenario, room state should be lazy loaded and partial.
// There should be only Alice and state.members.count = 1
- (void)checkRoomStateWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        [room state:^(MXRoomState *roomState) {

            MXRoomMembers *lazyloadedRoomMembers = roomState.members;

            XCTAssert([lazyloadedRoomMembers memberWithUserId:aliceSession.myUser.userId]);

            if (lazyLoading)
            {
                XCTAssertEqual(lazyloadedRoomMembers.members.count, 1, @"There should be only Alice in the lazy loaded room state");

                XCTAssertEqual(roomState.membersCount.members, 1);
                XCTAssertEqual(roomState.membersCount.joined, 1);
                XCTAssertEqual(roomState.membersCount.invited, 0);
            }
            else
            {
                // The room members list in the room state is full known
                XCTAssertEqual(lazyloadedRoomMembers.members.count, 4);

                XCTAssertEqual(roomState.membersCount.members, 4);
                XCTAssertEqual(roomState.membersCount.joined, 3);
                XCTAssertEqual(roomState.membersCount.invited, 1);
            }

            [expectation fulfill];
        }];
    }];
}

- (void)testRoomState
{
    [self checkRoomStateWithLazyLoading:YES];
}

- (void)testRoomStateWithLazyLoadingOFF
{
    [self checkRoomStateWithLazyLoading:NO];
}

// Check lazy loaded romm state when Charlie sends a new message
- (void)checkRoomStateOnIncomingMessage:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *messageFromCharlie = @"A new message from Charlie";

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room liveTimeline:^(MXEventTimeline *liveTimeline) {

            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqualObjects(event.content[@"body"], messageFromCharlie);

                XCTAssert([roomState.members memberWithUserId:aliceSession.myUser.userId]);
                XCTAssert([roomState.members memberWithUserId:charlieSession.myUser.userId]);

                if (lazyLoading)
                {
                    XCTAssertEqual(roomState.members.members.count, 2, @"There should only Alice and Charlie now in the lazy loaded room state");

                    XCTAssertEqual(roomState.membersCount.members, 2);
                    XCTAssertEqual(roomState.membersCount.joined, 2);
                    XCTAssertEqual(roomState.membersCount.invited, 0);
                }
                else
                {
                    // The room members list in the room state is full known
                    XCTAssertEqual(roomState.members.members.count, 4);

                    XCTAssertEqual(roomState.membersCount.members, 4);
                    XCTAssertEqual(roomState.membersCount.joined, 3);
                    XCTAssertEqual(roomState.membersCount.invited, 1);
                }

                [expectation fulfill];
            }];

            MXRoom *roomFromCharliePOV = [charlieSession roomWithRoomId:roomId];
            [roomFromCharliePOV sendTextMessage:messageFromCharlie success:nil failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        }];
    }];
}

- (void)testRoomStateOnIncomingMessage
{
    [self checkRoomStateOnIncomingMessage:YES];
}

- (void)testRoomStateOnIncomingMessageLazyLoadingOFF
{
    [self checkRoomStateOnIncomingMessage:NO];
}


// When paginating back to the beginning, lazy loaded room state passed in pagination callback must be updated with Bob, then Charlie and Dave.
- (void)checkRoomStateWhilePaginatingWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room liveTimeline:^(MXEventTimeline *liveTimeline) {

            __block NSUInteger messageCount = 0;
            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                switch (++messageCount) {
                    case 50:
                        if (lazyLoading)
                        {
                            XCTAssertNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                            XCTAssertNil([liveTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                            XCTAssertNil([liveTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                        }
                        else
                        {
                            XCTAssertNotNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
                        }

                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                        break;
                    case 51:
                        XCTAssert([roomState.members memberWithUserId:bobSession.myUser.userId]);

                        if (lazyLoading)
                        {
                            XCTAssertNil([roomState.members memberWithUserId:charlieSession.myUser.userId]);
                            XCTAssertNil([liveTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                        }
                        else
                        {
                            XCTAssert([roomState.members memberWithUserId:charlieSession.myUser.userId]);
                        }

                        // The room state of the room should have been enriched
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:bobSession.myUser.userId]);

                        break;

                    case 110:
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:aliceSession.myUser.userId]);
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:bobSession.myUser.userId]);
                        XCTAssertNotNil([liveTimeline.state.members memberWithUserId:charlieSession.myUser.userId]);
                        break;

                    default:
                        break;
                }
            }];

            // Paginate the 50 last message where there is only Alice talking
            [liveTimeline resetPagination];
            [liveTimeline paginate:50 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                // Pagine a bit more to get Bob's message
                [liveTimeline paginate:25 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                    // Paginate all to get a full room state
                    [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

                        XCTAssertGreaterThan(messageCount, 110, @"The test has not fully run");

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testRoomStateWhilePaginating
{
    [self checkRoomStateWhilePaginatingWithLazyLoading:YES];
}

- (void)testRoomStateWhilePaginatingWithLazyLoadingOFF
{
    [self checkRoomStateWhilePaginatingWithLazyLoading:NO];
}


// As members is only partial, [room members:] should trigger an HTTP request
// and returns the 4 persons,
- (void)checkRoomMembersWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        MXHTTPOperation *operation = [room members:^(MXRoomMembers *roomMembers) {

            // The room members list in the room state is full known
            XCTAssertEqual(roomMembers.members.count, 4);
            XCTAssertEqual(roomMembers.joinedMembers.count, 3);
            XCTAssertEqual([roomMembers membersWithMembership:MXMembershipInvite].count, 1);

            [expectation fulfill];
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

        if (lazyLoading)
        {
            XCTAssert(operation.operation, @"As members is only partial, [room members:] should trigger an HTTP request");
        }
        else
        {
            XCTAssertNil(operation.operation);
        }
    }];
}

- (void)testRoomMembers
{
    [self checkRoomMembersWithLazyLoading:YES];
}

- (void)testRoomMembersWithLazyLoadingOFF
{
    [self checkRoomMembersWithLazyLoading:NO];
}

// [MXRoom members:] should make an HTTP request to fetch members only once
- (void)checkSingleRoomMembersRequestWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room members:^(MXRoomMembers *members) {

            MXHTTPOperation *operation = [room members:^(MXRoomMembers *roomMembers) {

                // The room members list in the room state is full known
                XCTAssertEqual(roomMembers.members.count, 4);
                XCTAssertEqual(roomMembers.joinedMembers.count, 3);
                XCTAssertEqual([roomMembers membersWithMembership:MXMembershipInvite].count, 1);

                [expectation fulfill];
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

            XCTAssertNil(operation.operation);

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSingleRoomMembersRequest
{
    [self checkSingleRoomMembersRequestWithLazyLoading:YES];
}

- (void)testSingleRoomMembersRequestWithLazyLoadingOFF
{
    [self checkSingleRoomMembersRequestWithLazyLoading:NO];
}


// Check [room members:lazyLoadedMembers:] callbacks call
- (void)checkRoomMembersAndLazyLoadedMembersWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];

        [room members:^(MXRoomMembers *members) {

            // The room members list in the room state is full known
            XCTAssertEqual(members.members.count, 4);
            XCTAssertEqual(members.joinedMembers.count, 3);
            XCTAssertEqual([members membersWithMembership:MXMembershipInvite].count, 1);

            [expectation fulfill];

        } lazyLoadedMembers:^(MXRoomMembers *lazyLoadedMembers) {

            if (lazyLoading)
            {
                XCTAssertEqual(lazyLoadedMembers.members.count, 1, @"There should be only Alice in the lazy loaded room state");
                XCTAssertEqual(lazyLoadedMembers.joinedMembers.count, 1);
                XCTAssertEqual([lazyLoadedMembers membersWithMembership:MXMembershipInvite].count, 0);
            }
            else
            {
                XCTFail(@"This block should not be called when we already know all room members");
            }

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomMembersAndLazyLoadedMembers
{
    [self checkRoomMembersAndLazyLoadedMembersWithLazyLoading:YES];
}

- (void)testRoomMembersAndLazyLoadedMembersWithLazyLoadingOFF
{
    [self checkRoomMembersAndLazyLoadedMembersWithLazyLoading:NO];
}


// roomSummary.membersCount must be right in both cases
- (void)checkRoomSummaryMembersCountWithLazyLoading:(BOOL)lazyLoading
{
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoomSummary *roomSummary = [aliceSession roomSummaryWithRoomId:roomId];

        XCTAssertEqual(roomSummary.membersCount.members, 4);
        XCTAssertEqual(roomSummary.membersCount.joined, 3);
        XCTAssertEqual(roomSummary.membersCount.invited, 1);

        [expectation fulfill];
    }];
}

- (void)testRoomSummaryMembersCount
{
    [self checkRoomSummaryMembersCountWithLazyLoading:YES];
}

- (void)testRoomSummaryMembersCountWithLazyLoadingOFF
{
    [self checkRoomSummaryMembersCountWithLazyLoading:NO];
}


// Check room display name computed from heroes provided in the room summary
- (void)checkRoomSummaryDisplayNameFromHeroesWithLazyLoading:(BOOL)lazyLoading
{
    // Do not set a room name for this test
    [self createScenarioWithLazyLoading:lazyLoading inARoomWithName:NO readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {

        MXRoom *room = [aliceSession roomWithRoomId:roomId];
        [room state:^(MXRoomState *roomState) {

            // Membership events for heroes must have been lazy-loaded
            // There are used to compute roomSummary.displayname
            XCTAssertNotNil([roomState.members memberWithUserId:aliceSession.myUser.userId]);
            XCTAssertNotNil([roomState.members memberWithUserId:bobSession.myUser.userId]);
            XCTAssertNotNil([roomState.members memberWithUserId:charlieSession.myUser.userId]);

            MXRoomSummary *roomSummary = [aliceSession roomSummaryWithRoomId:roomId];

            if (lazyLoading)
            {
                XCTAssertNotNil(roomSummary.displayname, @"Thanks to the summary api, the SDK can build a room display name");
            }
            else
            {
                XCTAssertNil(roomSummary.displayname);
            }

            [expectation fulfill];
        }];
    }];
}

- (void)testRoomSummaryDisplayNameFromHeroes
{
    [self checkRoomSummaryDisplayNameFromHeroesWithLazyLoading:YES];
}

- (void)testRoomSummaryDisplayNameFromHeroesWithLazyLoadingOFF
{
    [self checkRoomSummaryDisplayNameFromHeroesWithLazyLoading:NO];
}


// Check encryption from a lazy loaded room state
// - Alice sends a message from its lazy loaded room state where there is no Charlie
// - Charlie must be able to decrypt it
- (void)checkEncryptedMessage:(BOOL)lazyLoading
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;
    [self createScenarioWithLazyLoading:lazyLoading readyToTest:^(MXSession *aliceSession, MXSession *bobSession, MXSession *charlieSession, NSString *roomId, XCTestExpectation *expectation) {
        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        MXRoom *roomFromBobPOV = [bobSession roomWithRoomId:roomId];
        [roomFromBobPOV enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

            aliceSession.crypto.warnOnUnknowDevices = NO;

            NSString *messageFromAlice = @"An encrypted message";

            [charlieSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

                XCTAssertTrue(event.isEncrypted);
                XCTAssert(event.clearEvent);
                XCTAssertEqualObjects(event.content[@"body"], messageFromAlice);

                [expectation fulfill];
            }];

            MXRoom *room = [aliceSession roomWithRoomId:roomId];
            [room sendTextMessage:messageFromAlice success:nil failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testEncryptedMessage
{
    [self checkEncryptedMessage:YES];
}

- (void)testEncryptedMessageWithLazyLoadingOFF
{
    [self checkEncryptedMessage:NO];
}


/*
 @TODO(lazy-loading):
 - test while paginating around a permalink
 - test read receipts
 */
@end

#pragma clang diagnostic pop

