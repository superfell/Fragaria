//
//  FragariaAppDelegate.h
//  Fragaria
//
//  Created by Jonathan on 30/04/2010.
//  Copyright 2010 mugginsoft.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MGSFragaria/MGSFragaria.h>

@class SMLTextView;
@class MGSFragaria;
@class MGSSimpleBreakpointDelegate;

@interface FragariaAppDelegate : NSObject <NSApplicationDelegate, MGSFragariaTextViewDelegate, SMLSyntaxColouringDelegate, MGSDragOperationDelegate>

- (IBAction)copyToPasteBoard:(id)sender;
- (IBAction)reloadString:(id)sender;

@property (weak) IBOutlet NSWindow *window;

@property (nonatomic,assign) NSString *syntaxDefinition;


@end
