//
//  VT100XtermParserTest.m
//  iTerm2
//
//  Created by George Nachman on 12/30/14.
//
//

#import "VT100XtermParserTest.h"
#import "CVector.h"
#import "iTermParser.h"
#import "VT100XtermParser.h"
#import "VT100Token.h"

@implementation VT100XtermParserTest {
    NSMutableDictionary *_savedState;
    iTermParserContext _context;
    CVector _incidentals;
}

- (void)setup {
    _savedState = [NSMutableDictionary dictionary];
    CVectorCreate(&_incidentals, 1);
}

- (void)teardown {
    CVectorDestroy(&_incidentals);
}

- (VT100Token *)tokenForDataWithFormat:(NSString *)formatString, ... {
    va_list args;
    va_start(args, formatString);
    NSString *string = [[[NSString alloc] initWithFormat:formatString arguments:args] autorelease];
    va_end(args);

    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    VT100Token *token = [[[VT100Token alloc] init] autorelease];
    _context = iTermParserContextMake((unsigned char *)data.bytes, data.length);
    [VT100XtermParser decodeFromContext:&_context
                            incidentals:&_incidentals
                                  token:token
                               encoding:NSUTF8StringEncoding
                             savedState:_savedState];
    return token;
}

- (void)testNoModeYet {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]", ESC];
    assert(token->type == VT100_WAIT);

    // In case saved state gets used, verify it can continue from there.
    token = [self tokenForDataWithFormat:@"%c]0;title%c", ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testWellFormedSetWindowTitleTerminatedByBell {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;title%c", ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testWellFormedSetWindowTitleTerminatedByST {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;title%c\\", ESC, ESC];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testIgnoreEmbeddedOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%c]tle%c", ESC, ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testIgnoreEmbeddedOSCTwoPart_OutOfDataAfterBracket {
    // Running out of data just after an embedded ESC ] hits a special path.
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%c]", ESC, ESC];
    assert(token->type == VT100_WAIT);

    token = [self tokenForDataWithFormat:@"%c]0;ti%c]tle%c", ESC, ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testIgnoreEmbeddedOSCTwoPart_OutOfDataAfterEsc {
    // Running out of data just after an embedded ESC hits a special path.
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%c", ESC, ESC];
    assert(token->type == VT100_WAIT);

    token = [self tokenForDataWithFormat:@"%c]0;ti%c]tle%c", ESC, ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"title"]);
}

- (void)testFailOnEmbddedEscapePlusCharacter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;ti%cc", ESC, ESC];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testNonstandardLinuxSetPalette {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]Pa123456", ESC];
    assert(token->type == XTERMCC_SET_PALETTE);
    assert([token.string isEqualToString:@"a123456"]);
}

- (void)testUnsupportedFirstParameterNoTerminator {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testUnsupportedFirstParameter {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x%c", ESC, VT100CC_BEL];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testPartialNonstandardLinuxSetPalette {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]Pa12345", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testCancelAbortsOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0%c", ESC, VT100CC_CAN];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testSubstituteAbortsOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0%c", ESC, VT100CC_SUB];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testUnfinishedMultitoken {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 2);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    assert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    assert([header.kvpKey isEqualToString:@"File"]);
    assert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    assert(body->type = XTERMCC_MULTITOKEN_BODY);
    assert([body.string isEqualToString:@"abc"]);
}

- (void)testCompleteMultitoken {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c",
                         ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_MULTITOKEN_END);
    assert(CVectorCount(&_incidentals) == 2);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    assert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    assert([header.kvpKey isEqualToString:@"File"]);
    assert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    assert(body->type = XTERMCC_MULTITOKEN_BODY);
    assert([body.string isEqualToString:@"abc"]);
}

- (void)testCompleteMultitokenInMultiplePasses {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 0);

    // Give it some more header
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 0);

    // Give it the final colon so the header can be parsed
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 1);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    assert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    assert([header.kvpKey isEqualToString:@"File"]);
    assert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    // Give it some body.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:a", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 2);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    assert(body->type = XTERMCC_MULTITOKEN_BODY);
    assert([body.string isEqualToString:@"a"]);

    // More body
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 3);

    body = CVectorGetObject(&_incidentals, 2);
    assert(body->type = XTERMCC_MULTITOKEN_BODY);
    assert([body.string isEqualToString:@"bc"]);

    // Start finishing up
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c", ESC, ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 3);

    // And, done.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c\\", ESC, ESC];
    assert(token->type == XTERMCC_MULTITOKEN_END);
    assert(CVectorCount(&_incidentals) == 3);
}

- (void)testLateFailureMultitokenInMultiplePasses {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1337;File=blah;", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 0);

    // Give it some more header
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 0);

    // Give it the final colon so the header can be parsed
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 1);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    assert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    assert([header.kvpKey isEqualToString:@"File"]);
    assert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    // Give it some body.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:a", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 2);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    assert(body->type = XTERMCC_MULTITOKEN_BODY);
    assert([body.string isEqualToString:@"a"]);

    // More body
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 3);

    body = CVectorGetObject(&_incidentals, 2);
    assert(body->type = XTERMCC_MULTITOKEN_BODY);
    assert([body.string isEqualToString:@"bc"]);

    // Now a bogus character.
    token = [self tokenForDataWithFormat:@"%c]1337;File=blah;foo=bar:abc%c", ESC, VT100CC_SUB];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testUnfinishedMultitokenWithDeprecatedMode {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]50;File=blah;foo=bar:abc", ESC];
    assert(token->type == VT100_WAIT);
    assert(CVectorCount(&_incidentals) == 2);

    VT100Token *header = CVectorGetObject(&_incidentals, 0);
    assert(header->type = XTERMCC_MULTITOKEN_HEADER_SET_KVP);
    assert([header.kvpKey isEqualToString:@"File"]);
    assert([header.kvpValue isEqualToString:@"blah;foo=bar"]);

    VT100Token *body = CVectorGetObject(&_incidentals, 1);
    assert(body->type = XTERMCC_MULTITOKEN_BODY);
    assert([body.string isEqualToString:@"abc"]);
}

- (void)testUnterminatedOSCWaits {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;foo", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testUnterminateOSCWaits_2 {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0", ESC];
    assert(token->type == VT100_WAIT);
}

- (void)testMultiPartOSC {
    // Pass in a partial escape code. The already-parsed data should be saved in the saved-state
    // dictionary.
    VT100Token *token = [self tokenForDataWithFormat:@"%c]0;foo", ESC];
    assert(token->type == VT100_WAIT);
    assert(_savedState.allKeys.count > 0);

    // Give it a more-formed code. The first three characters have changed. Normally they would be
    // the same, but it's done here to ensure that they are ignored.
    token = [self tokenForDataWithFormat:@"%c]0;XXXbar", ESC];
    assert(token->type == VT100_WAIT);
    assert(_savedState.allKeys.count > 0);

    // Now a fully-formed code. The entire string value must come from saved state.
    token = [self tokenForDataWithFormat:@"%c]0;XXXXXX%c", ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_WINICON_TITLE);
    assert([token.string isEqualToString:@"foobar"]);
}

- (void)testEmbeddedColon {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1;foo:bar%c", ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_ICON_TITLE);
    assert([token.string isEqualToString:@"foo:bar"]);
}

- (void)testUnsupportedMode {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]999;foo%c", ESC, VT100CC_BEL];
    assert(token->type == VT100_NOTSUPPORT);
}

- (void)testBelAfterEmbeddedOSC {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]1;%c]%c", ESC, ESC, VT100CC_BEL];
    assert(token->type == XTERMCC_ICON_TITLE);
    assert([token.string isEqualToString:@""]);
}

- (void)testIgnoreEmbeddedOSCWhenFailing {
    VT100Token *token = [self tokenForDataWithFormat:@"%c]x%c]%c", ESC, ESC, VT100CC_BEL];
    assert(token->type == VT100_NOTSUPPORT);
    assert(iTermParserNumberOfBytesConsumed(&_context) == 6);
}

@end
