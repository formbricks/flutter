// Patrol's bridge: runs each Dart test in patrol_test/ as one XCUITest.
// From the Patrol setup guide (https://patrol.leancode.co/documentation).
@import XCTest;
@import patrol;
@import ObjectiveC.runtime;

#if !defined(PATROL_INTEGRATION_TEST_IOS_RUNNER)
#import "PatrolIntegrationTestIosRunner.h"
#endif

PATROL_INTEGRATION_TEST_IOS_RUNNER(RunnerUITests)
