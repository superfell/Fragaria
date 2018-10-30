/*

 MGSFragaria
 Written by Jonathan Mitchell, jonathan@mugginsoft.com
 Find the latest version at https://github.com/mugginsoft/Fragaria
 
 Smultron version 3.6b1, 2009-09-12
 Written by Peter Borg, pgw3@mac.com
 Find the latest version at http://smultron.sourceforge.net

 Licensed under the Apache License, Version 2.0 (the "License"); you may not use
 this file except in compliance with the License. You may obtain a copy of the
 License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed
 under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 CONDITIONS OF ANY KIND, either express or implied. See the License for the
 specific language governing permissions and limitations under the License.
*/

#import "SMLSyntaxColouring.h"
#import "MGSSyntaxDefinition.h"
#import "SMLLayoutManager.h"
#import "MGSSyntaxController.h"
#import "SMLTextView.h"
#import "NSScanner+Fragaria.h"
#import "MGSColourScheme.h"


// syntax colouring information dictionary keys
NSString *SMLSyntaxGroup = @"group";
NSString *SMLSyntaxGroupID = @"groupID";
NSString *SMLSyntaxWillColour = @"willColour";
NSString *SMLSyntaxAttributes = @"attributes";
NSString *SMLSyntaxInfo = @"syntaxInfo";

// syntax colouring group names
NSString *SMLSyntaxGroupNumber = @"number";
NSString *SMLSyntaxGroupCommand = @"command";
NSString *SMLSyntaxGroupInstruction = @"instruction";
NSString *SMLSyntaxGroupKeyword = @"keyword";
NSString *SMLSyntaxGroupAutoComplete = @"autocomplete";
NSString *SMLSyntaxGroupVariable = @"variable";
NSString *SMLSyntaxGroupFirstString = @"firstString";
NSString *SMLSyntaxGroupSecondString = @"secondString";
NSString *SMLSyntaxGroupAttribute = @"attribute";
NSString *SMLSyntaxGroupSingleLineComment = @"singleLineComment";
NSString *SMLSyntaxGroupMultiLineComment = @"multiLineComment";
NSString *SMLSyntaxGroupSecondStringPass2 = @"secondStringPass2";

// syntax colouring group IDs
enum {
    kSMLSyntaxGroupNumber = 0,
    kSMLSyntaxGroupCommand = 1,
    kSMLSyntaxGroupInstruction = 2,
    kSMLSyntaxGroupKeyword = 3,
    kSMLSyntaxGroupAutoComplete = 4,
    kSMLSyntaxGroupVariable = 5,
    kSMLSyntaxGroupSecondString = 6,
    kSMLSyntaxGroupFirstString = 7,
    kSMLSyntaxGroupAttribute = 8,
    kSMLSyntaxGroupSingleLineComment = 9,
    kSMLSyntaxGroupMultiLineComment = 10,
    kSMLSyntaxGroupSecondStringPass2 = 11,
    kSMLCountOfSyntaxGroups = 12
};
typedef NSInteger SMLSyntaxGroupInteger;


@interface SMLSyntaxColouring()

@property (nonatomic, assign) BOOL coloursChanged;

@end


@implementation SMLSyntaxColouring {
    SMLLayoutManager __weak *layoutManager;

    NSDictionary *commandsColour, *commentsColour, *instructionsColour;
    NSDictionary *keywordsColour, *autocompleteWordsColour, *stringsColour;
    NSDictionary *variablesColour, *attributesColour, *numbersColour;
    
    NSString *firstStringPattern, *secondStringPattern;
    NSString *firstMultilineStringPattern, *secondMultilineStringPattern;
}


@synthesize layoutManager;


#pragma mark - Instance methods


/*
 * - initWithLayoutManager:
 */
- (instancetype)initWithLayoutManager:(SMLLayoutManager *)lm
{
    if ((self = [super init])) {
        layoutManager = lm;
        
        _inspectedCharacterIndexes = [[NSMutableIndexSet alloc] init];

        // configure colouring
        _coloursOnlyUntilEndOfLine = YES;
        _colourScheme = [[MGSColourScheme alloc] init];
        [self rebuildAttributesCache];

        [self layoutManagerDidChangeTextStorage];
	}
    
    return self;
}


#pragma mark - Colour Scheme Updating


- (void)setColourScheme:(MGSColourScheme *)colourScheme
{
    _colourScheme = colourScheme;
    [self rebuildAttributesCache];
    [self invalidateAllColouring];
}


#pragma mark - Text change notification


- (void)textStorageDidProcessEditing:(NSNotification*)notification
{
    NSTextStorage *ts = [notification object];
    
    if (!(ts.editedMask & NSTextStorageEditedCharacters))
        return;
    
    NSRange newRange = [ts editedRange];
    NSRange oldRange = newRange;
    NSInteger changeInLength = [ts changeInLength];
    NSMutableIndexSet *insp = self.inspectedCharacterIndexes;
    
    oldRange.length -= changeInLength;
    [insp shiftIndexesStartingAtIndex:NSMaxRange(oldRange) by:changeInLength];
    newRange = [[ts string] lineRangeForRange:newRange];
    [insp removeIndexesInRange:newRange];
}


#pragma mark - Property getters/setters


- (void)layoutManagerWillChangeTextStorage
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSTextStorageDidProcessEditingNotification
                object:layoutManager.textStorage];
}


- (void)layoutManagerDidChangeTextStorage
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(textStorageDidProcessEditing:)
               name:NSTextStorageDidProcessEditingNotification object:layoutManager.textStorage];
}


/*
 *  @property syntaxDefinition
 */
- (void)setSyntaxDefinition:(MGSSyntaxDefinition *)syntaxDefinition
{
    _syntaxDefinition = syntaxDefinition;
    [self prepareRegularExpressions];
    [self invalidateAllColouring];
}

/*
 *  @property syntaxDefinitionName
 */
- (void)setSyntaxDefinitionName:(NSString *)syntaxDefinitionName
{
	NSDictionary *syntaxDict;
	MGSSyntaxDefinition *syntaxDef;
	
	syntaxDict = [[MGSSyntaxController sharedInstance] syntaxDictionaryWithName:syntaxDefinitionName];
    syntaxDef = [[MGSSyntaxDefinition alloc] initFromSyntaxDictionary:syntaxDict name:syntaxDefinitionName];
	[self setSyntaxDefinition:syntaxDef];
}

- (NSString*)syntaxDefinitionName
{
    return self.syntaxDefinition.name;
}


/*
 *  @property colourMultiLineStrings
 */
- (void)setColoursMultiLineStrings:(BOOL)coloursMultiLineStrings
{
    _coloursMultiLineStrings = coloursMultiLineStrings;
    [self invalidateAllColouring];
}

/*
 *  @property coloursOnlyUntilEndOfLine
 */
- (void)setColoursOnlyUntilEndOfLine:(BOOL)coloursOnlyUntilEndOfLine
{
    _coloursOnlyUntilEndOfLine = coloursOnlyUntilEndOfLine;
    [self invalidateAllColouring];
}


/*
 * - isSyntaxColouringRequired
 */
- (BOOL)isSyntaxColouringRequired
{
    return self.syntaxDefinition && self.syntaxDefinition.syntaxDefinitionAllowsColouring;
}


- (NSTextStorage *)textStorage
{
    return layoutManager.textStorage;
}


#pragma mark - Colouring


/*
 * - rebuildAttributesCache
 */
- (void)rebuildAttributesCache
{
    commandsColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForCommands,
                       SMLSyntaxGroup: SMLSyntaxGroupCommand};
    commentsColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForComments,
                       SMLSyntaxGroup: @"comments"};
    instructionsColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForInstructions,
                           SMLSyntaxGroup: SMLSyntaxGroupInstruction};
    keywordsColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForKeywords,
                       SMLSyntaxGroup: SMLSyntaxGroupKeyword};
    autocompleteWordsColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForAutocomplete,
                                SMLSyntaxGroup: SMLSyntaxGroupAutoComplete};
    stringsColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForStrings,
                      SMLSyntaxGroup: @"strings"};
    variablesColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForVariables,
                        SMLSyntaxGroup: SMLSyntaxGroupVariable};
    attributesColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForAttributes,
                         SMLSyntaxGroup: SMLSyntaxGroupAttribute};
    numbersColour = @{NSForegroundColorAttributeName: self.colourScheme.colourForNumbers,
                      SMLSyntaxGroup: SMLSyntaxGroupNumber};
    
    [self invalidateAllColouring];
}


- (void)prepareRegularExpressions
{
    NSString *firstString = self.syntaxDefinition.firstString;
    NSString *secondString = self.syntaxDefinition.secondString;
    
    firstStringPattern = [NSString stringWithFormat:@"\\W%@[^%@\\\\\\r\\n]*+(?:\\\\(?:.|$)[^%@\\\\\\r\\n]*+)*+%@", firstString, firstString, firstString, firstString];
    
    secondStringPattern = [NSString stringWithFormat:@"\\W%@[^%@\\\\\\r\\n]*+(?:\\\\(?:.|$)[^%@\\\\]*+)*+%@", secondString, secondString, secondString, secondString];
    
    firstMultilineStringPattern = [NSString stringWithFormat:@"\\W%@[^%@\\\\]*+(?:\\\\(?:.|$)[^%@\\\\]*+)*+%@", firstString, firstString, firstString, firstString];
    
    secondMultilineStringPattern = [NSString stringWithFormat:@"\\W%@[^%@\\\\]*+(?:\\\\(?:.|$)[^%@\\\\]*+)*+%@", secondString, secondString, secondString, secondString];
}


/*
 * - invalidateAllColouring
 */
- (void)invalidateAllColouring
{
    NSString *string;
    
    string = self.layoutManager.textStorage.string;
	NSRange wholeRange = NSMakeRange(0, [string length]);
    
	[self resetColourInRange:wholeRange];
    [self.inspectedCharacterIndexes removeAllIndexes];
}


/*
 * - invalidateVisibleRange
 */
- (void)invalidateVisibleRangeOfTextView:(SMLTextView *)textView
{
    NSMutableIndexSet *validRanges;

    validRanges = self.inspectedCharacterIndexes;
    NSRect visibleRect = [[[textView enclosingScrollView] contentView] documentVisibleRect];
    NSRange visibleRange = [[textView layoutManager] glyphRangeForBoundingRect:visibleRect inTextContainer:[textView textContainer]];
    [validRanges removeIndexesInRange:visibleRange];
}


/*
 * - recolourRange:
 */
- (void)recolourRange:(NSRange)range
{
    NSMutableIndexSet *invalidRanges;
    
	if (!self.isSyntaxColouringRequired) return;
 
    [self.textStorage beginEditing];

    invalidRanges = [NSMutableIndexSet indexSetWithIndexesInRange:range];
    [invalidRanges removeIndexes:self.inspectedCharacterIndexes];
    [invalidRanges enumerateRangesUsingBlock:^(NSRange range, BOOL *stop){
        if (![self.inspectedCharacterIndexes containsIndexesInRange:range]) {
            NSRange nowValid = [self recolourChangedRange:range];
            [self.inspectedCharacterIndexes addIndexesInRange:nowValid];
        }
    }];
    
    [self.textStorage endEditing];
}


/*
 * - recolourChangedRange:
 */
- (NSRange)recolourChangedRange:(NSRange)rangeToRecolour
{
    // setup
    NSString *documentString = self.layoutManager.textStorage.string;
	NSRange effectiveRange = [documentString lineRangeForRange:rangeToRecolour];

    // trace
    //NSLog(@"rangeToRecolor location %i length %i", rangeToRecolour.location, rangeToRecolour.length);

    // adjust effective range
    //
    // When multiline strings are coloured we need to scan backwards to
    // find where the string might have started if it's "above" the top of the screen,
    // or we need to scan forwards to find where a multiline string which wraps off
    // the range ends.
    //
    // This is not always correct but it's better than nothing.
    //
	if (self.coloursMultiLineStrings) {
		NSInteger beginFirstStringInMultiLine = [documentString rangeOfString:self.syntaxDefinition.firstString options:NSBackwardsSearch range:NSMakeRange(0, effectiveRange.location)].location;
        if (beginFirstStringInMultiLine != NSNotFound) {
            if ([[self syntaxColouringGroupOfCharacterAtIndex:beginFirstStringInMultiLine] isEqual:@"strings"]) {
                NSInteger startOfLine = [documentString lineRangeForRange:NSMakeRange(beginFirstStringInMultiLine, 0)].location;
                effectiveRange = NSMakeRange(startOfLine, rangeToRecolour.length + (rangeToRecolour.location - startOfLine));
            }
        }
        
        
        NSInteger lastStringBegin = [documentString rangeOfString:self.syntaxDefinition.firstString options:NSBackwardsSearch range:rangeToRecolour].location;
        if (lastStringBegin != NSNotFound) {
            NSRange restOfString = NSMakeRange(NSMaxRange(rangeToRecolour), 0);
            restOfString.length = [documentString length] - restOfString.location;
            NSInteger lastStringEnd = [documentString rangeOfString:self.syntaxDefinition.firstString options:0 range:restOfString].location;
            if (lastStringEnd != NSNotFound) {
                NSInteger endOfLine = NSMaxRange([documentString lineRangeForRange:NSMakeRange(lastStringEnd, 0)]);
                effectiveRange = NSUnionRange(effectiveRange, NSMakeRange(lastStringBegin, endOfLine-lastStringBegin));
            }
        }
	}
    
    /* Expand the range to not start or end in the middle of an already coloured
     * block. */
    NSRange longRange;
    NSRange wholeRange = NSMakeRange(0, [documentString length]);
    
    if ([self.textStorage attribute:SMLSyntaxGroup atIndex:effectiveRange.location longestEffectiveRange:&longRange inRange:wholeRange]) {
        effectiveRange = NSUnionRange(effectiveRange, longRange);
    }
    if (NSMaxRange(effectiveRange) < self.textStorage.length && [self.textStorage attribute:SMLSyntaxGroup atIndex:NSMaxRange(effectiveRange) longestEffectiveRange:&longRange inRange:wholeRange]) {
        effectiveRange = NSUnionRange(effectiveRange, longRange);
    }
    
    // assign range string
	NSString *rangeString = [documentString substringWithRange:effectiveRange];
	NSUInteger rangeStringLength = [rangeString length];
	if (rangeStringLength == 0) {
		return effectiveRange;
	}
    
    // allocate the range scanner
	NSScanner *rangeScanner = [[NSScanner alloc] initWithString:rangeString];
	[rangeScanner setCharactersToBeSkipped:nil];
    
    // allocate the document scanner
	NSScanner *documentScanner = [[NSScanner alloc] initWithString:documentString];
	[documentScanner setCharactersToBeSkipped:nil];
	
    // uncolour the range
	[self resetColourInRange:effectiveRange];
	
    // define a block that the colour delegate can use to affect colouring
    BOOL (^colourRangeBlock)(NSDictionary *, NSRange) = ^(NSDictionary *colourInfo, NSRange range) {
        [self setColour:colourInfo range:range];
        
        // at the moment we always succeed
        return YES;
    };
    
    @try {
        for (NSInteger i = 0; i < kSMLCountOfSyntaxGroups; i++) {
            /* Colour all syntax groups */
            [self colourGroupWithIdentifier:i inRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner colouringBlock:colourRangeBlock];
        }
    } @catch (NSException *exception) {
		NSLog(@"Syntax colouring exception: %@", exception);
	}

    return effectiveRange;
}


#pragma mark - Coloring passes


- (void)colourGroupWithIdentifier:(NSInteger)group inRange:(NSRange)effectiveRange withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner colouringBlock:(BOOL(^)(NSDictionary *, NSRange))colourRangeBlock
{
    NSString *groupName;
    BOOL doColouring = YES;
    NSDictionary *attributes;
    
    switch (group) {
        case kSMLSyntaxGroupNumber:
            groupName = SMLSyntaxGroupNumber;
            doColouring = self.colourScheme.coloursNumbers;
            attributes = numbersColour;
            break;
        case kSMLSyntaxGroupCommand:
            groupName = SMLSyntaxGroupCommand;
            doColouring = self.colourScheme.coloursCommands && ![self.syntaxDefinition.beginCommand isEqual:@""];
            attributes = commandsColour;
            break;
        case kSMLSyntaxGroupInstruction:
            groupName = SMLSyntaxGroupInstruction;
            doColouring = self.colourScheme.coloursInstructions && (![self.syntaxDefinition.beginInstruction isEqual:@""] || self.syntaxDefinition.instructions);
            attributes = instructionsColour;
            break;
        case kSMLSyntaxGroupKeyword:
            groupName = SMLSyntaxGroupKeyword;
            doColouring = self.colourScheme.coloursKeywords && [self.syntaxDefinition.keywords count] > 0;
            attributes = keywordsColour;
            break;
        case kSMLSyntaxGroupAutoComplete:
            groupName = SMLSyntaxGroupAutoComplete;
            doColouring = self.colourScheme.coloursAutocomplete && [self.syntaxDefinition.autocompleteWords count] > 0;
            attributes = autocompleteWordsColour;
            break;
        case kSMLSyntaxGroupVariable:
            groupName = SMLSyntaxGroupVariable;
            doColouring = self.colourScheme.coloursVariables && (self.syntaxDefinition.beginVariableCharacterSet || self.syntaxDefinition.variableRegex);
            attributes = variablesColour;
            break;
        case kSMLSyntaxGroupSecondString:
            groupName = SMLSyntaxGroupSecondString;
            doColouring = self.colourScheme.coloursStrings && ![self.syntaxDefinition.secondString isEqual:@""];
            attributes = stringsColour;
            break;
        case kSMLSyntaxGroupFirstString:
            groupName = SMLSyntaxGroupFirstString;
            doColouring = self.colourScheme.coloursStrings && ![self.syntaxDefinition.firstString isEqual:@""];
            attributes = stringsColour;
            break;
        case kSMLSyntaxGroupAttribute:
            groupName = SMLSyntaxGroupAttribute;
            doColouring = self.colourScheme.coloursAttributes;
            attributes = attributesColour;
            break;
        case kSMLSyntaxGroupSingleLineComment:
            groupName = SMLSyntaxGroupSingleLineComment;
            doColouring = self.colourScheme.coloursComments;
            attributes = commentsColour;
            break;
        case kSMLSyntaxGroupMultiLineComment:
            groupName = SMLSyntaxGroupMultiLineComment;
            doColouring = self.colourScheme.coloursComments;
            attributes = commentsColour;
            break;
        case kSMLSyntaxGroupSecondStringPass2:
            groupName = SMLSyntaxGroupSecondStringPass2;
            doColouring = self.colourScheme.coloursStrings && ![self.syntaxDefinition.secondString isEqual:@""];
            attributes = stringsColour;
            break;
        default:
            [NSException raise:@"Bug" format:@"Unrecognized syntax group identifier %ld", (long)group];
    }
    
    if (!doColouring) return;
        
    // reset scanner
    [rangeScanner mgs_setScanLocation:0];
    [documentScanner mgs_setScanLocation:0];
    
    switch (group) {
        case kSMLSyntaxGroupNumber:
            [self colourNumbersInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupCommand:
            [self colourCommandsInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupInstruction:
            [self colourInstructionsInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupKeyword:
            [self colourKeywordsInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupAutoComplete:
            [self colourAutocompleteInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupVariable:
            [self colourVariablesInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupSecondString:
            [self colourSecondStrings1InRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupFirstString:
            [self colourFirstStringsInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupAttribute:
            [self colourAttributesInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupSingleLineComment:
            [self colourSingleLineCommentsInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupMultiLineComment:
            [self colourMultiLineCommentsInRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
            break;
        case kSMLSyntaxGroupSecondStringPass2:
            [self colourSecondStrings2InRange:effectiveRange withRangeScanner:rangeScanner documentScanner:documentScanner];
    }
}


- (void)colourNumbersInRange:(NSRange)colouringRange withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSInteger colourStartLocation, colourEndLocation, queryLocation;
    NSInteger rangeLocation = colouringRange.location;
    unichar testCharacter;
    NSString *documentString = [documentScanner string];
    NSString *rangeString = [rangeScanner string];
    
    
    if (self.syntaxDefinition.numberDefinition) {
        [self colourMatchesOfPattern:self.syntaxDefinition.numberDefinition withAttributes:numbersColour inRange:colouringRange];
        return;
    }
    
    
    // scan range to end
    while (![rangeScanner isAtEnd]) {
        
        // scan up to a number character
        [rangeScanner scanUpToCharactersFromSet:self.syntaxDefinition.numberCharacterSet intoString:NULL];
        colourStartLocation = [rangeScanner scanLocation];
        
        // scan to number end
        [rangeScanner scanCharactersFromSet:self.syntaxDefinition.numberCharacterSet intoString:NULL];
        colourEndLocation = [rangeScanner scanLocation];
        
        if (colourStartLocation == colourEndLocation) {
            break;
        }
        
        // don't colour if preceding character is a letter.
        // this prevents us from colouring numbers in variable names,
        queryLocation = colourStartLocation + rangeLocation;
        if (queryLocation > 0) {
            testCharacter = [documentString characterAtIndex:queryLocation - 1];
            
            // numbers can occur in variable, class and function names
            // eg: var_1 should not be coloured as a number
            if ([self.syntaxDefinition.nameCharacterSet characterIsMember:testCharacter]) {
                continue;
            }
        }
        
        // @todo: handle constructs such as 1..5 which may occur within some loop constructs
        
        // don't colour a trailing decimal point as some languages may use it as a line terminator
        if (colourEndLocation > 0) {
            queryLocation = colourEndLocation - 1;
            testCharacter = [rangeString characterAtIndex:queryLocation];
            if (testCharacter == self.syntaxDefinition.decimalPointCharacter) {
                colourEndLocation--;
            }
        }
        
        [self setColour:numbersColour range:NSMakeRange(colourStartLocation + rangeLocation, colourEndLocation - colourStartLocation)];
    }
}


- (void)colourCommandsInRange:(NSRange)colouringRange withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSInteger colourStartLocation;
    NSInteger rangeLocation = colouringRange.location;
    NSUInteger endOfLine;
    NSInteger searchSyntaxLength = [self.syntaxDefinition.endCommand length];
    unichar beginCommandCharacter = [self.syntaxDefinition.beginCommand characterAtIndex:0];
    unichar endCommandCharacter = [self.syntaxDefinition.endCommand characterAtIndex:0];
    NSString *rangeString = [rangeScanner string];
    
    // reset scanner
    [rangeScanner mgs_setScanLocation:0];
    
    // scan range to end
    while (![rangeScanner isAtEnd]) {
        [rangeScanner scanUpToString:self.syntaxDefinition.beginCommand intoString:nil];
        colourStartLocation = [rangeScanner scanLocation];
        endOfLine = NSMaxRange([rangeString lineRangeForRange:NSMakeRange(colourStartLocation, 0)]);
        if (![rangeScanner scanUpToString:self.syntaxDefinition.endCommand intoString:nil] || [rangeScanner scanLocation] >= endOfLine) {
            [rangeScanner mgs_setScanLocation:endOfLine];
            continue; // Don't colour it if it hasn't got a closing tag
        } else {
            // To avoid problems with strings like <yada <%=yada%> yada> we need to balance the number of begin- and end-tags
            // If ever there's a beginCommand or endCommand with more than one character then do a check first
            NSUInteger commandLocation = colourStartLocation + 1;
            NSUInteger skipEndCommand = 0;
            
            while (commandLocation < endOfLine) {
                unichar commandCharacterTest = [rangeString characterAtIndex:commandLocation];
                if (commandCharacterTest == endCommandCharacter) {
                    if (!skipEndCommand) {
                        break;
                    } else {
                        skipEndCommand--;
                    }
                }
                if (commandCharacterTest == beginCommandCharacter) {
                    skipEndCommand++;
                }
                commandLocation++;
            }
            if (commandLocation < endOfLine) {
                [rangeScanner mgs_setScanLocation:commandLocation + searchSyntaxLength];
            } else {
                [rangeScanner mgs_setScanLocation:endOfLine];
            }
        }
        
        [self setColour:commandsColour range:NSMakeRange(colourStartLocation + rangeLocation, [rangeScanner scanLocation] - colourStartLocation)];
    }
}


- (void)colourInstructionsInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSInteger colourStartLocation, beginLocationInMultiLine, endLocationInMultiLine;
    NSInteger rangeLocation = rangeToRecolour.location;
    NSRange searchRange;
    NSString *documentString = [documentScanner string];
    NSUInteger documentStringLength = [documentString length];
    NSUInteger maxRangeLocation = NSMaxRange(rangeToRecolour);
    
    if (self.syntaxDefinition.instructions) {
        [self colourKeywordsFromSet:self.syntaxDefinition.instructions withAttributes:instructionsColour inRange:rangeToRecolour withRangeScanner:rangeScanner documentScanner:documentScanner];
        return;
    }
    
    // It takes too long to scan the whole document if it's large, so for instructions, first multi-line comment and second multi-line comment search backwards and begin at the start of the first beginInstruction etc. that it finds from the present position and, below, break the loop if it has passed the scanned range (i.e. after the end instruction)
    
    beginLocationInMultiLine = [documentString rangeOfString:self.syntaxDefinition.beginInstruction options:NSBackwardsSearch range:NSMakeRange(0, rangeLocation)].location;
    endLocationInMultiLine = [documentString rangeOfString:self.syntaxDefinition.endInstruction options:NSBackwardsSearch range:NSMakeRange(0, rangeLocation)].location;
    if (beginLocationInMultiLine == NSNotFound || (endLocationInMultiLine != NSNotFound && beginLocationInMultiLine < endLocationInMultiLine)) {
        beginLocationInMultiLine = rangeLocation;
    }
    
    NSInteger searchSyntaxLength = [self.syntaxDefinition.endInstruction length];
    
    // scan document to end
    while (![documentScanner isAtEnd]) {
        searchRange = NSMakeRange(beginLocationInMultiLine, rangeToRecolour.length);
        if (NSMaxRange(searchRange) > documentStringLength) {
            searchRange = NSMakeRange(beginLocationInMultiLine, documentStringLength - beginLocationInMultiLine);
        }
        
        colourStartLocation = [documentString rangeOfString:self.syntaxDefinition.beginInstruction options:NSLiteralSearch range:searchRange].location;
        if (colourStartLocation == NSNotFound) {
            break;
        }
        [documentScanner mgs_setScanLocation:colourStartLocation];
        if (![documentScanner scanUpToString:self.syntaxDefinition.endInstruction intoString:nil] || [documentScanner scanLocation] >= documentStringLength) {
            if (self.coloursOnlyUntilEndOfLine) {
                [documentScanner mgs_setScanLocation:NSMaxRange([documentString lineRangeForRange:NSMakeRange(colourStartLocation, 0)])];
            } else {
                [documentScanner mgs_setScanLocation:documentStringLength];
            }
        } else {
            if ([documentScanner scanLocation] + searchSyntaxLength <= documentStringLength) {
                [documentScanner mgs_setScanLocation:[documentScanner scanLocation] + searchSyntaxLength];
            }
        }
        
        [self setColour:instructionsColour range:NSMakeRange(colourStartLocation, [documentScanner scanLocation] - colourStartLocation)];
        if ([documentScanner scanLocation] > maxRangeLocation) {
            break;
        }
        beginLocationInMultiLine = [documentScanner scanLocation];
    }
}


- (void)colourKeywordsInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    [self colourKeywordsFromSet:self.syntaxDefinition.keywords withAttributes:keywordsColour inRange:rangeToRecolour withRangeScanner:rangeScanner documentScanner:documentScanner];
}


- (void)colourAutocompleteInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    [self colourKeywordsFromSet:self.syntaxDefinition.autocompleteWords withAttributes:autocompleteWordsColour inRange:rangeToRecolour withRangeScanner:rangeScanner documentScanner:documentScanner];
}


- (void)colourVariablesInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSUInteger colourStartLocation;
    NSInteger rangeLocation = rangeToRecolour.location;
    NSUInteger endOfLine, colourLength;
    NSString *rangeString = [rangeScanner string];
    NSUInteger rangeStringLength = [rangeString length];
    
    if (self.syntaxDefinition.variableRegex) {
        [self colourMatchesOfPattern:self.syntaxDefinition.variableRegex withAttributes:variablesColour inRange:rangeToRecolour];
        return;
    }
    
    // scan range to end
    while (![rangeScanner isAtEnd]) {
        [rangeScanner scanUpToCharactersFromSet:self.syntaxDefinition.beginVariableCharacterSet intoString:nil];
        colourStartLocation = [rangeScanner scanLocation];
        if (colourStartLocation + 1 < rangeStringLength) {
            if ([[self.syntaxDefinition.singleLineComments firstObject] isEqual:@"%"] && [rangeString characterAtIndex:colourStartLocation + 1] == '%') { // To avoid a problem in LaTex with \%
                if ([rangeScanner scanLocation] < rangeStringLength) {
                    [rangeScanner mgs_setScanLocation:colourStartLocation + 1];
                }
                continue;
            }
        }
        endOfLine = NSMaxRange([rangeString lineRangeForRange:NSMakeRange(colourStartLocation, 0)]);
        if (![rangeScanner scanUpToCharactersFromSet:self.syntaxDefinition.endVariableCharacterSet intoString:nil] || [rangeScanner scanLocation] >= endOfLine) {
            [rangeScanner mgs_setScanLocation:endOfLine];
            colourLength = [rangeScanner scanLocation] - colourStartLocation;
        } else {
            colourLength = [rangeScanner scanLocation] - colourStartLocation;
            if ([rangeScanner scanLocation] < rangeStringLength) {
                [rangeScanner mgs_setScanLocation:[rangeScanner scanLocation] + 1];
            }
        }
        
        [self setColour:variablesColour range:NSMakeRange(colourStartLocation + rangeLocation, colourLength)];
    }
}


- (void)colourSecondStrings1InRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSString *stringPattern;
    NSRegularExpression *regex;
    NSError *error;
    NSString *rangeString = [rangeScanner string];
    NSInteger rangeLocation = rangeToRecolour.location;
    
    if (!self.coloursMultiLineStrings)
        stringPattern = secondStringPattern;
    else
        stringPattern = secondMultilineStringPattern;
    
    regex = [NSRegularExpression regularExpressionWithPattern:stringPattern options:0 error:&error];
    if (error) return;
    
    [regex enumerateMatchesInString:rangeString options:0 range:NSMakeRange(0, [rangeString length]) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSRange foundRange = [match range];
        [self setColour:self->stringsColour range:NSMakeRange(foundRange.location + rangeLocation + 1, foundRange.length - 1)];
    }];
}


- (void)colourFirstStringsInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSString *stringPattern;
    NSRegularExpression *regex;
    NSError *error;
    NSString *rangeString = [rangeScanner string];
    NSInteger rangeLocation = rangeToRecolour.location;
    
    if (!self.coloursMultiLineStrings)
        stringPattern = firstStringPattern;
    else
        stringPattern = firstMultilineStringPattern;
    
    regex = [NSRegularExpression regularExpressionWithPattern:stringPattern options:0 error:&error];
    if (error) return;
    
    [regex enumerateMatchesInString:rangeString options:0 range:NSMakeRange(0, [rangeString length]) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSRange foundRange = [match range];
        if ([[self syntaxColouringGroupOfCharacterAtIndex:foundRange.location + rangeLocation] isEqual:@"strings"])
            return;
        [self setColour:self->stringsColour range:NSMakeRange(foundRange.location + rangeLocation + 1, foundRange.length - 1)];
    }];
}


- (void)colourAttributesInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSUInteger colourStartLocation, colourEndLocation;
    NSInteger rangeLocation = rangeToRecolour.location;
    NSString *documentString = [documentScanner string];
    NSString *rangeString = [rangeScanner string];
    NSUInteger rangeStringLength = [rangeString length];
    
    // scan range to end
    while (![rangeScanner isAtEnd]) {
        [rangeScanner scanUpToString:@" " intoString:nil];
        colourStartLocation = [rangeScanner scanLocation];
        if (colourStartLocation + 1 < rangeStringLength) {
            [rangeScanner mgs_setScanLocation:colourStartLocation + 1];
        } else {
            break;
        }
        if (![[self syntaxColouringGroupOfCharacterAtIndex:(colourStartLocation + rangeLocation)] isEqual:SMLSyntaxGroupCommand]) {
            continue;
        }
        
        [rangeScanner scanCharactersFromSet:self.syntaxDefinition.attributesCharacterSet intoString:nil];
        colourEndLocation = [rangeScanner scanLocation];
        
        if (colourEndLocation + 1 < rangeStringLength) {
            [rangeScanner mgs_setScanLocation:[rangeScanner scanLocation] + 1];
        }
        
        if ([documentString characterAtIndex:colourEndLocation + rangeLocation] == '=') {
            [self setColour:attributesColour range:NSMakeRange(colourStartLocation + rangeLocation, colourEndLocation - colourStartLocation)];
        }
    }
}


- (void)colourSingleLineCommentsInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSUInteger colourStartLocation, endOfLine;
    NSRange rangeOfLine;
    NSInteger rangeLocation = rangeToRecolour.location;
    NSString *documentString = [documentScanner string];
    NSString *rangeString = [rangeScanner string];
    NSUInteger rangeStringLength = [rangeString length];
    NSUInteger documentStringLength = [documentString length];
    NSUInteger searchSyntaxLength;
    
    if (self.syntaxDefinition.singleLineCommentRegex) {
        [self colourMatchesOfPattern:self.syntaxDefinition.singleLineCommentRegex withAttributes:commentsColour inRange:rangeToRecolour];
        return;
    }
    
    for (NSString *singleLineComment in self.syntaxDefinition.singleLineComments) {
        if (![singleLineComment isEqualToString:@""]) {
            
            // reset scanner
            [rangeScanner mgs_setScanLocation:0];
            searchSyntaxLength = [singleLineComment length];
            
            // scan range to end
            while (![rangeScanner isAtEnd]) {
                
                // scan for comment
                [rangeScanner scanUpToString:singleLineComment intoString:nil];
                colourStartLocation = [rangeScanner scanLocation];
                
                // common case handling
                if ([singleLineComment isEqualToString:@"//"]) {
                    if (colourStartLocation > 0 && [rangeString characterAtIndex:colourStartLocation - 1] == ':') {
                        [rangeScanner mgs_setScanLocation:colourStartLocation + 1];
                        continue; // To avoid http:// ftp:// file:// etc.
                    }
                } else if ([singleLineComment isEqualToString:@"#"]) {
                    if (rangeStringLength > 1) {
                        rangeOfLine = [rangeString lineRangeForRange:NSMakeRange(colourStartLocation, 0)];
                        if ([rangeString rangeOfString:@"#!" options:NSLiteralSearch range:rangeOfLine].location != NSNotFound) {
                            [rangeScanner mgs_setScanLocation:NSMaxRange(rangeOfLine)];
                            continue; // Don't treat the line as a comment if it begins with #!
                        } else if (colourStartLocation > 0 && [rangeString characterAtIndex:colourStartLocation - 1] == '$') {
                            [rangeScanner mgs_setScanLocation:colourStartLocation + 1];
                            continue; // To avoid $#
                        } else if (colourStartLocation > 0 && [rangeString characterAtIndex:colourStartLocation - 1] == '&') {
                            [rangeScanner mgs_setScanLocation:colourStartLocation + 1];
                            continue; // To avoid &#
                        }
                    }
                } else if ([singleLineComment isEqualToString:@"%"]) {
                    if (rangeStringLength > 1) {
                        if (colourStartLocation > 0 && [rangeString characterAtIndex:colourStartLocation - 1] == '\\') {
                            [rangeScanner mgs_setScanLocation:colourStartLocation + 1];
                            continue; // To avoid \% in LaTex
                        }
                    }
                }
                
                // If the comment is within an already coloured string then disregard it
                if (colourStartLocation + rangeLocation + searchSyntaxLength < documentStringLength) {
                    if ([[self syntaxColouringGroupOfCharacterAtIndex:colourStartLocation + rangeLocation] isEqual:@"strings"]) {
                        [rangeScanner mgs_setScanLocation:colourStartLocation + 1];
                        continue;
                    }
                }
                
                // this is a single line comment so we can scan to the end of the line
                /* We omit the newline characters from the coloring area to
                 * avoid merging adjacent single-line comments that span the 
                 * whole line. */
                [rangeString getLineStart:NULL end:NULL contentsEnd:&endOfLine forRange:NSMakeRange(colourStartLocation, 0)];
                [rangeScanner mgs_setScanLocation:endOfLine];
                
                // colour the comment
                [self setColour:commentsColour range:NSMakeRange(colourStartLocation + rangeLocation, [rangeScanner scanLocation] - colourStartLocation)];
            }
        }
    } // end for
}


- (void)colourMultiLineCommentsInRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSUInteger colourStartLocation, beginLocationInMultiLine, endLocationInMultiLine, colourLength;
    NSRange searchRange;
    NSInteger rangeLocation = rangeToRecolour.location;
    NSString *documentString = [documentScanner string];
    NSUInteger documentStringLength = [documentString length];
    NSUInteger searchSyntaxLength;
    NSUInteger maxRangeLocation = NSMaxRange(rangeToRecolour);
    
    for (NSArray *multiLineComment in self.syntaxDefinition.multiLineComments) {
        
        // Get strings
        NSString *beginMultiLineComment = [multiLineComment objectAtIndex:0];
        NSString *endMultiLineComment = [multiLineComment objectAtIndex:1];
        
        if (![beginMultiLineComment isEqualToString:@""]) {
            
            // Default to start of document
            beginLocationInMultiLine = 0;
            
            // If start and end comment markers are the the same we
            // always start searching at the beginning of the document.
            // Otherwise we must consider that our start location may be mid way through
            // a multiline comment.
            if (![beginMultiLineComment isEqualToString:endMultiLineComment]) {
                
                // Search backwards from range location looking for comment start
                beginLocationInMultiLine = [documentString rangeOfString:beginMultiLineComment options:NSBackwardsSearch range:NSMakeRange(0, rangeLocation)].location;
                endLocationInMultiLine = [documentString rangeOfString:endMultiLineComment options:NSBackwardsSearch range:NSMakeRange(0, rangeLocation)].location;
                
                // If comments not found then begin at range location
                if (beginLocationInMultiLine == NSNotFound || (endLocationInMultiLine != NSNotFound && beginLocationInMultiLine < endLocationInMultiLine)) {
                    beginLocationInMultiLine = rangeLocation;
                }
            }
            
            [documentScanner mgs_setScanLocation:beginLocationInMultiLine];
            searchSyntaxLength = [endMultiLineComment length];
            
            // Iterate over the document until we exceed our work range
            while (![documentScanner isAtEnd]) {
                
                // Search up to document end
                searchRange = NSMakeRange(beginLocationInMultiLine, documentStringLength - beginLocationInMultiLine);
                
                // Look for comment start in document
                colourStartLocation = [documentString rangeOfString:beginMultiLineComment options:NSLiteralSearch range:searchRange].location;
                if (colourStartLocation == NSNotFound) {
                    break;
                }
                
                // Increment our location.
                // This is necessary to cover situations, such as F-Script, where the start and end comment strings are identical
                if (colourStartLocation + 1 < documentStringLength) {
                    [documentScanner mgs_setScanLocation:colourStartLocation + 1];
                    
                    // If the comment is within a string disregard it
                    if ([[self syntaxColouringGroupOfCharacterAtIndex:colourStartLocation] isEqual:@"strings"]) {
                        beginLocationInMultiLine++;
                        continue;
                    }
                } else {
                    [documentScanner mgs_setScanLocation:colourStartLocation];
                }
                
                // Scan up to comment end
                if (![documentScanner scanUpToString:endMultiLineComment intoString:nil] || [documentScanner scanLocation] >= documentStringLength) {
                    
                    // Comment end not found
                    if (self.coloursOnlyUntilEndOfLine) {
                        [documentScanner mgs_setScanLocation:NSMaxRange([documentString lineRangeForRange:NSMakeRange(colourStartLocation, 0)])];
                    } else {
                        [documentScanner mgs_setScanLocation:documentStringLength];
                    }
                    colourLength = [documentScanner scanLocation] - colourStartLocation;
                } else {
                    
                    // Comment end found
                    if ([documentScanner scanLocation] < documentStringLength) {
                        
                        // Safely advance scanner
                        [documentScanner mgs_setScanLocation:[documentScanner scanLocation] + searchSyntaxLength];
                    }
                    colourLength = [documentScanner scanLocation] - colourStartLocation;
                    
                    // HTML specific
                    if ([endMultiLineComment isEqualToString:@"-->"]) {
                        [documentScanner scanUpToCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:nil]; // Search for the first letter after -->
                        if ([documentScanner scanLocation] + 6 < documentStringLength) {// Check if there's actually room for a </script>
                            if ([documentString rangeOfString:@"</script>" options:NSCaseInsensitiveSearch range:NSMakeRange([documentScanner scanLocation] - 2, 9)].location != NSNotFound || [documentString rangeOfString:@"</style>" options:NSCaseInsensitiveSearch range:NSMakeRange([documentScanner scanLocation] - 2, 8)].location != NSNotFound) {
                                beginLocationInMultiLine = [documentScanner scanLocation];
                                continue; // If the comment --> is followed by </script> or </style> it is probably not a real comment
                            }
                        }
                        [documentScanner mgs_setScanLocation:colourStartLocation + colourLength]; // Reset the scanner position
                    }
                }
                
                // Colour the range
                [self setColour:commentsColour range:NSMakeRange(colourStartLocation, colourLength)];
                
                // We may be done
                if ([documentScanner scanLocation] > maxRangeLocation) {
                    break;
                }
                
                // set start location for next search
                beginLocationInMultiLine = [documentScanner scanLocation];
            }
        }
    } // end for
}


- (void)colourSecondStrings2InRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSString *stringPattern;
    NSRegularExpression *regex;
    NSError *error;
    NSString *rangeString = [rangeScanner string];
    NSInteger rangeLocation = rangeToRecolour.location;
    
    if (!self.coloursMultiLineStrings)
        stringPattern = secondStringPattern;
    else
        stringPattern = secondMultilineStringPattern;
    
    regex = [NSRegularExpression regularExpressionWithPattern:stringPattern options:0 error:&error];
    if (error) return;
    
    [regex enumerateMatchesInString:rangeString options:0 range:NSMakeRange(0, [rangeString length]) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSRange foundRange = [match range];
        if ([[self syntaxColouringGroupOfCharacterAtIndex:foundRange.location + rangeLocation] isEqual:@"strings"] || [[self syntaxColouringGroupOfCharacterAtIndex:foundRange.location + rangeLocation] isEqual:@"comments"]) return;
        [self setColour:self->stringsColour range:NSMakeRange(foundRange.location + rangeLocation + 1, foundRange.length - 1)];
    }];
}


#pragma mark - Common colouring methods


- (void)colourKeywordsFromSet:(NSSet*)keywords withAttributes:(NSDictionary*)attributes inRange:(NSRange)rangeToRecolour withRangeScanner:(NSScanner*)rangeScanner documentScanner:(NSScanner*)documentScanner
{
    NSUInteger colourStartLocation, colourEndLocation;
    NSInteger rangeLocation = rangeToRecolour.location;
    NSString *documentString = [documentScanner string];
    NSString *rangeString = [rangeScanner string];
    NSUInteger rangeStringLength = [rangeString length];
    
    // scan range to end
    while (![rangeScanner isAtEnd]) {
        [rangeScanner scanUpToCharactersFromSet:self.syntaxDefinition.keywordStartCharacterSet intoString:nil];
        colourStartLocation = [rangeScanner scanLocation];
        if ((colourStartLocation + 1) < rangeStringLength) {
            [rangeScanner mgs_setScanLocation:(colourStartLocation + 1)];
        }
        [rangeScanner scanUpToCharactersFromSet:self.syntaxDefinition.keywordEndCharacterSet intoString:nil];
        
        colourEndLocation = [rangeScanner scanLocation];
        if (colourEndLocation > rangeStringLength || colourStartLocation == colourEndLocation) {
            break;
        }
        
        NSString *keywordTestString = nil;
        if (!self.syntaxDefinition.keywordsCaseSensitive) {
            keywordTestString = [[documentString substringWithRange:NSMakeRange(colourStartLocation + rangeLocation, colourEndLocation - colourStartLocation)] lowercaseString];
        } else {
            keywordTestString = [documentString substringWithRange:NSMakeRange(colourStartLocation + rangeLocation, colourEndLocation - colourStartLocation)];
        }
        if ([keywords containsObject:keywordTestString]) {
            if (!self.syntaxDefinition.recolourKeywordIfAlreadyColoured) {
                if ([[self syntaxColouringGroupOfCharacterAtIndex:colourStartLocation + rangeLocation] isEqual:SMLSyntaxGroupCommand]) {
                    continue;
                }
            }
            [self setColour:attributes range:NSMakeRange(colourStartLocation + rangeLocation, [rangeScanner scanLocation] - colourStartLocation)];
        }
    }
}


- (void)colourMatchesOfPattern:(NSString*)pattern withAttributes:(NSDictionary*)attributes inRange:(NSRange)colouringRange
{
    NSString *documentString = self.layoutManager.textStorage.string;
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if (!regex) return;
    
    [regex enumerateMatchesInString:documentString options:0 range:colouringRange usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        [self setColour:attributes range:[match range]];
    }];
}


#pragma mark - Coloring primitives


- (void)resetColourInRange:(NSRange)range
{
    [self.textStorage addAttribute:NSForegroundColorAttributeName value:self.colourScheme.textColor range:range];
    [self.textStorage removeAttribute:SMLSyntaxGroup range:range];
}


/*
 * - setColour:range:
 */
- (void)setColour:(NSDictionary *)colourDictionary range:(NSRange)range
{
    NSRange effectiveRange = NSMakeRange(0,0);
    NSRange bounds = NSMakeRange(0, [[layoutManager textStorage] length]);
    NSUInteger i = range.location;
    NSString *attr;
    NSSet *overlapSet = [NSSet setWithObjects:SMLSyntaxGroupCommand,
                         SMLSyntaxGroupInstruction, nil];
    
    while (NSLocationInRange(i, range)) {
        attr = [self.textStorage attribute:SMLSyntaxGroup atIndex:i
          longestEffectiveRange:&effectiveRange inRange:bounds];
        if (![overlapSet containsObject:attr]) {
            [self resetColourInRange:effectiveRange];
        }
        i = NSMaxRange(effectiveRange);
    }
	[self.textStorage addAttributes:colourDictionary range:range];
}


/*
 * - syntaxColouringGroupOfCharacterAtIndex:
 */
- (NSString*)syntaxColouringGroupOfCharacterAtIndex:(NSUInteger)index
{
    return [self.textStorage attribute:SMLSyntaxGroup atIndex:index effectiveRange:NULL];
}


@end
