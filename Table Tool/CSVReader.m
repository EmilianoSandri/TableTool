//
//  CSVReader.m
//  Table Tool
//
//  Created by Andreas Aigner on 09.07.15.
//  Copyright (c) 2015 Egger Apps. All rights reserved.
//

#import "CSVReader.h"

@interface CSVReader () {
    NSScanner *dataScanner;
    NSString *dataString;
	NSMutableCharacterSet *newlineCharacterSet;
	NSMutableCharacterSet *quoteEndedCharacterSet;
    NSMutableCharacterSet *quoteAndEscapeSet;
    BOOL unquoted;
}

@end


@implementation CSVReader

-(instancetype)initWithData:(NSData *)data configuration:(CSVConfiguration *)config{
    self = [super init];
    if(self) {
        _data = data;
        [self initVariables:config];
    }
    return self;
}

-(instancetype)initWithString:(NSString *)newDataString configuration:(CSVConfiguration *)config{
    self = [super init];
    if(self) {
        dataString = newDataString;
        [self initVariables:config];
    }
    return self;
}

-(void)initVariables:(CSVConfiguration *)config{
    _config = config.copy;
    if([_config.quoteCharacter isEqualToString:@""]) unquoted = YES;
    _atEnd = NO;
}


-(BOOL)initScannerWithError:(NSError **)outError skipQuotes:(BOOL)skip{
    if(!dataScanner){
        if(skip){
            _config.columnSeparator = @"\t";
            _config.quoteCharacter = @"";
        }
        
        if(!dataString){
            dataString = [[NSString alloc] initWithData:_data encoding:_config.encoding];
        }
        
        if(!dataString) {
            if(outError != NULL) {
                *outError = [NSError errorWithDomain:@"at.eggerapps.Table-Tool" code:1 userInfo: @{NSLocalizedDescriptionKey: @"Could not read data", NSLocalizedRecoverySuggestionErrorKey:@"Try specifying a different encoding."}];
            }
            return NO;
        }
        dataScanner = [NSScanner scannerWithString:dataString];
        dataScanner.caseSensitive = YES;
        dataScanner.charactersToBeSkipped = nil;
        
		newlineCharacterSet = [NSCharacterSet newlineCharacterSet].mutableCopy;
		[newlineCharacterSet removeCharactersInString:@"\x0b\x0c"];
        quoteEndedCharacterSet = newlineCharacterSet.mutableCopy;
        [quoteEndedCharacterSet addCharactersInString:_config.columnSeparator];
        quoteAndEscapeSet = [[NSMutableCharacterSet alloc]init];
        [quoteAndEscapeSet addCharactersInString:_config.quoteCharacter];
        [quoteAndEscapeSet addCharactersInString:_config.escapeCharacter];
    }
    
    return YES;
}

-(NSArray *)readLineWithError:(NSError *__autoreleasing *)outError {
    
    NSError *scannerError = nil;
    BOOL didInitializeScanner = [self initScannerWithError:&scannerError skipQuotes:NO];
    if(!didInitializeScanner) {
        if(outError){
            *outError = scannerError;
        }
        return nil;
    }
    
    NSMutableArray *rowArray = [[NSMutableArray alloc]init];
    
    while(!_atEnd){
        NSString *scannedString = nil;
        NSError *scanError = nil;
        
        BOOL didScan = NO;
        if(!unquoted){
            didScan = [self scanQuotedValueIntoString:&scannedString error:&scanError];
        }
        
        if((!didScan && scanError == nil)){
            didScan = [self scanUnquotedValueIntoString:&scannedString error:&scanError];
        }
        
        if(!didScan) {
            if(outError){
                *outError = scanError;
            }
            return nil;
        }
        
       [rowArray addObject:scannedString];
        
        if(dataScanner.isAtEnd){
            _atEnd = YES;
            break;
        }
        
        if([newlineCharacterSet characterIsMember:[dataString characterAtIndex:dataScanner.scanLocation]]){
            dataScanner.scanLocation++;
			if(dataScanner.isAtEnd) _atEnd = YES;
            break;
        }
        
        //scanning column separator
        dataScanner.scanLocation++;
    }
    
    if (_atEnd && !rowArray.count) {
        return nil;
    }
    
    return rowArray;
}

-(NSArray *)readLineForPastingTo:(NSArray *)tableColumnsOrder maxColumnIndex:(long)maxColumnNumber {
    
    [self initScannerWithError:NULL skipQuotes:YES];
    NSMutableArray *rowArray = [[NSMutableArray alloc]init];
    for(int i = 0; i < maxColumnNumber; i++){
        [rowArray addObject:@""];
    }
    
    for(int i = 0;;i++) {
        NSString *scannedString = nil;
        
        [self scanUnquotedValueIntoString:&scannedString error:NULL];
        
        if(tableColumnsOrder.count > i){
                [rowArray replaceObjectAtIndex:[tableColumnsOrder[i] integerValue] withObject:scannedString];
        } else {
                [rowArray addObject:scannedString];
        }
        
        if(dataScanner.isAtEnd){
            _atEnd = YES;
            break;
        }
        
        if([newlineCharacterSet characterIsMember:[dataString characterAtIndex:dataScanner.scanLocation]]){
            dataScanner.scanLocation++;
            break;
        }
        
        //scanning column separator
        dataScanner.scanLocation++;
    }
    
    return rowArray;
}

-(BOOL)scanQuotedValueIntoString:(NSString **)scannedString error:(NSError**)outError {
    
    if(dataScanner.isAtEnd) {
        *scannedString = @"";
        return YES;
    }
    
    if([dataString characterAtIndex:dataScanner.scanLocation] != '\"'){
        return NO;
    }
    
    NSMutableString *temporaryString = [[NSMutableString alloc] init];
    dataScanner.scanLocation++;
    
    while(!dataScanner.isAtEnd){
        while(!dataScanner.isAtEnd && ![quoteAndEscapeSet characterIsMember:[dataString characterAtIndex:dataScanner.scanLocation]]){
            [temporaryString appendString:[dataString substringWithRange:NSMakeRange(dataScanner.scanLocation, 1)]];
            dataScanner.scanLocation++;
        }
        
        if(dataScanner.isAtEnd){
            if(outError != NULL) {
                *outError = [NSError errorWithDomain:@"at.eggerapps.Table-Tool" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Could not read data", NSLocalizedRecoverySuggestionErrorKey:@"Try specifying a different separator or quote."}];
            }
            return NO;
        }
        
        if([dataString characterAtIndex:dataScanner.scanLocation] == [_config.escapeCharacter characterAtIndex:0]) {
            if([_config.escapeCharacter isEqualToString:_config.quoteCharacter]){
                if((dataScanner.scanLocation+2 <= dataString.length && [quoteEndedCharacterSet characterIsMember:[dataString characterAtIndex:dataScanner.scanLocation+1]]) || dataScanner.scanLocation+1 == dataString.length){
                    dataScanner.scanLocation++;
                    *scannedString = temporaryString;
                    [self checkForCRLF];
                    return YES;
                }
            }
            
            dataScanner.scanLocation++;
            if(dataScanner.isAtEnd){
                if(outError != NULL) {
                    *outError = [NSError errorWithDomain:@"at.eggerapps.Table-Tool" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Could not read data", NSLocalizedRecoverySuggestionErrorKey:@"Try specifying a different separator or quote."}];
                }
                return NO;
            }
            [temporaryString appendString:[dataString substringWithRange:NSMakeRange(dataScanner.scanLocation,1)]];
            dataScanner.scanLocation++;
            continue;
        }
        
        if([dataString characterAtIndex:dataScanner.scanLocation] == [_config.quoteCharacter characterAtIndex:0]) {
            dataScanner.scanLocation++;
            if(dataScanner.isAtEnd || [quoteEndedCharacterSet characterIsMember:[dataString characterAtIndex:dataScanner.scanLocation]]){
                *scannedString = temporaryString;
                [self checkForCRLF];
                return YES;
            }
            if(outError != NULL) {
                *outError = [NSError errorWithDomain:@"at.eggerapps.Table-Tool" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Could not read data", NSLocalizedRecoverySuggestionErrorKey:@"Try specifying a different separator or quote."}];
            }
            return NO;
        }
        
    }
    if(outError != NULL) {
        *outError = [NSError errorWithDomain:@"at.eggerapps.Table-Tool" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Could not read data", NSLocalizedRecoverySuggestionErrorKey:@"Try specifying a different separator or quote."}];
    }
    return NO;
}

-(BOOL)scanUnquotedValueIntoString:(NSString **)scannedString error:(NSError **)outError{
    
    NSMutableString *temporaryString = [[NSMutableString alloc]initWithString:@""];
    while(!dataScanner.isAtEnd && ![quoteEndedCharacterSet characterIsMember:[dataString characterAtIndex:dataScanner.scanLocation]]){
        if([dataString characterAtIndex:dataScanner.scanLocation] == '\"' && !unquoted){
            if(outError != NULL) {
                *outError = [NSError errorWithDomain:@"at.eggerapps.Table-Tool" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Could not read data", NSLocalizedRecoverySuggestionErrorKey:@"Try specifying a different separator or quote."}];
            }
            return NO;
        }
        [temporaryString appendString:[dataString substringWithRange:NSMakeRange(dataScanner.scanLocation, 1)]];
        dataScanner.scanLocation++;
    }
    *scannedString = temporaryString;
    [self checkForCRLF];
    return YES;
}

-(void)reset{
    dataScanner = nil;
}

-(void)checkForCRLF{
    if(dataScanner.scanLocation + 2 > dataString.length) return;
    if([dataString characterAtIndex:dataScanner.scanLocation] == '\r' && [dataString characterAtIndex:dataScanner.scanLocation+1] == '\n'){
        dataScanner.scanLocation++;
    }
}

@end

