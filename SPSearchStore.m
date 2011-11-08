//
//  SPSearchStore.m
//  SPSearchStore
//
//	v0.9
//
//  Created by Philip Dow on 6/6/11.
//  Copyright 2011 Philip Dow /Sprouted. All rights reserved.
//	phil@phildow.net / phil@getsprouted.com
//

/*
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 * Neither the name of the author nor the names of its contributors may be used to endorse or
 promote products derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
 WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
 TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// Basically, you can use the code in your free, commercial, private and public projects
// as long as you include the above notice and attribute the code to Philip Dow / Sprouted
// If you use this code in an app send me a note. I'd love to know how the code is used.

#import "SPSearchStore.h"

NSString const * kSPSearchStoreIndexName = @"Search Index";
NSInteger const kSPSearchStoreMemorySize = 2^16;

static NSTimeInterval kSPSearchStoreDefaultFetchTime = 0.5;
static NSInteger kSPSearchStoreDefaultFetchCount = 100;

static NSDictionary * SPSearchStoreStopWords() {
	
	// Stop words dictionary. Currently only supports english but it hould be easy
	// to add other language specific stop words. Simply expand the stopWords
	// dictionary by adding a string of words separated by single space for the
	// value, followed by the two character language specifier for the key.
	
	// Other possible English stop words:
	// about against under with away also across ago been before after above below 
	// around vs up down while
	
	static NSDictionary *stopWords = nil;
	if ( stopWords == nil ) {
		stopWords = [[NSDictionary alloc] initWithObjectsAndKeys:
				@"a all am an and any are as at be but by can could did do does etc for from goes got had has have he her hers him his how if in is it its let me more much must my no nor not now of off on or our own see set shall she should so some than that the them then there these they this those though to too us was way we what when where which who why will would yes yet you your yours",
				@"en",
				nil];
	}
	
	return stopWords;
}

static NSMutableDictionary * SPSearchStoreTextAnalysisOptions() {
	
	// This dictionary stores a default set of text analysis options which are
	// specified during search index creation. They cover preferences such as
	// stop words, term length, proximity indexing and so on. 
	
	static NSMutableDictionary *textAnalysis = nil;
	if ( textAnalysis == nil ) {
		textAnalysis = [[NSMutableDictionary alloc] init];
			
		[textAnalysis setObject:[NSNumber numberWithBool:NO] forKey:(NSString *)kSKProximityIndexing];
		[textAnalysis setObject:[NSNumber numberWithInteger:0] forKey:(NSString *)kSKMaximumTerms];
		[textAnalysis setObject:[NSNumber numberWithInteger:1] forKey:(NSString *)kSKMinTermLength];
	}
	
	return textAnalysis;
}

#pragma mark -

@interface SPSearchStore()

@property (readwrite,retain) NSMutableData *storeData;
@property (readwrite,retain) NSURL *storeURL;

@property (readwrite,copy) NSDictionary *analysisOptions;
@property (readwrite,copy) NSSet *stopWords;
@property (readwrite) BOOL didCreateStore;

#pragma mark -

- (BOOL) _addDocument:(NSURL*)inDocumentURI withText:(NSString*)inContents;
- (BOOL) _addDocument:(NSURL*)inFileURL typeHint:(NSString*)inMimeHint;
- (BOOL) _removeDocument:(NSURL*)inDocumentURI;

- (NSArray*) _allDocumentsForDocumentRef:(SKDocumentRef)document ignoreEmptyDocuments:(BOOL)ignoresEmpty;

- (BOOL) _fetchResults:(NSArray**)outDocuments ranks:(float*)outRanks 
		maxTime:(CFTimeInterval)maxTime maxCount:(CFIndex)maxCount;

- (void) _incrementChangeCount;
- (BOOL) _flushIndexIfNecessary;
- (BOOL) _compactIndex;

@end

#pragma mark -

@implementation SPSearchStore

@synthesize searchIndex;
@synthesize storeData;
@synthesize storeURL;

@synthesize writeLock;
@synthesize readLock;

@synthesize didCreateStore;
@synthesize analysisOptions;
@synthesize stopWords;

@synthesize usesSpotlightImporters;
@synthesize usesConcurrentIndexing;
@synthesize ignoresNumericTerms;

@synthesize fetchCount;
@synthesize fetchTime;

#pragma mark -

- (id) initStoreWithMemory:(NSMutableData*)inData type:(SKIndexType)inType {
	
	NSAssert( inType!=kSKIndexUnknown, @"inType must not be kSKIndexUnknown (0)" );
	
	if ( self = [super init] ) {
		
		if ( inData == nil ) {
			// create a new in memory store
			
			inData = [NSMutableData dataWithCapacity: kSPSearchStoreMemorySize];
			searchIndex = SKIndexCreateWithMutableData( (CFMutableDataRef)inData, (CFStringRef)NULL,
					(SKIndexType)inType, (CFDictionaryRef)SPSearchStoreTextAnalysisOptions() );
		}
		else {
			// open a store from memory
			
			searchIndex = SKIndexOpenWithMutableData ( (CFMutableDataRef)inData, (CFStringRef)NULL );
		}
		
		if ( searchIndex == NULL ) {
			[self release];
			return nil;
		}
		
		writeLock = [[NSLock alloc] init];
		readLock = [[NSLock alloc] init];
		
		self.stopWords = [SPSearchStoreTextAnalysisOptions() objectForKey:(NSString*)kSKStopWords];
		self.analysisOptions = SPSearchStoreTextAnalysisOptions();
		self.didCreateStore = (inData==nil);
		self.storeData = inData;
		self.storeURL = nil;
		
		self.fetchCount = kSPSearchStoreDefaultFetchCount;
		self.fetchTime = kSPSearchStoreDefaultFetchTime;
		
		indexType = inType;
		changeCount = 0;
		
	}
	return self;
}

- (id) initStoreWithFilename:(NSString*)inPath type:(SKIndexType)inType {
	
	NSAssert( inPath!=nil, @"inPath must not be nil");
	NSAssert( inType!=kSKIndexUnknown, @"inType must not be kSKIndexUnknown (0)" );
	
	return [self initStoreWithURL:[NSURL fileURLWithPath:inPath] type:inType];
}

- (id) initStoreWithURL:(NSURL*)inFileURL type:(SKIndexType)inType {
	
	NSAssert( inFileURL!=nil, @"inFileURL must not be nil");
	NSAssert( [inFileURL isFileURL], @"inFileURL must be a file url");
	NSAssert( inType!=kSKIndexUnknown, @"inType must not be kSKIndexUnknown (0)" );
	
	if ( self = [super init] ) {
		
		NSFileManager *fm = [[[NSFileManager alloc] init] autorelease];
		BOOL fileExists = [fm fileExistsAtPath:[inFileURL path]];
		
		if ( fileExists ) {
			// store already exists, we want to open it
			
			searchIndex = SKIndexOpenWithURL((CFURLRef)inFileURL, (CFStringRef)NULL, true);
		}
		else {
			// store does not exist, we want to create it
			
			searchIndex = SKIndexCreateWithURL((CFURLRef)inFileURL, (CFStringRef)NULL, 
					(SKIndexType)inType, (CFDictionaryRef)SPSearchStoreTextAnalysisOptions() );
		}
		
		if ( searchIndex == NULL ) {
			[self release];
			return nil;
		}
		
		writeLock = [[NSLock alloc] init];
		readLock = [[NSLock alloc] init];
		
		self.stopWords = [SPSearchStoreTextAnalysisOptions() objectForKey:(NSString*)kSKStopWords];
		self.analysisOptions = SPSearchStoreTextAnalysisOptions();
		self.didCreateStore = !fileExists;
		self.storeURL = inFileURL;
		self.storeData = nil;
		
		self.fetchCount = kSPSearchStoreDefaultFetchCount;
		self.fetchTime = kSPSearchStoreDefaultFetchTime;
		
		indexType = inType;
		changeCount = 0;
		
	}
	return self;
}

- (void) dealloc {
	
	self.analysisOptions = nil;
	self.storeData = nil;
	self.storeURL = nil;
	
	SKIndexClose(searchIndex);
	searchIndex = NULL;
	
	[writeLock release], writeLock = nil;
	[readLock release], readLock = nil;
	[indexQue release], indexQue = nil;
	
	[super dealloc];
}

#pragma mark -

- (void) setUsesSpotlightImporters:(BOOL)useSpotlight {
	usesSpotlightImporters = useSpotlight;

	if ( useSpotlight ) SKLoadDefaultExtractorPlugIns();
}

- (void) setUsesConcurrentIndexing:(BOOL)useConcurrent {
	usesConcurrentIndexing = useConcurrent;
	
	if ( useConcurrent && indexQue == nil ) {
		indexQue = [[NSOperationQueue alloc] init];
		[indexQue setMaxConcurrentOperationCount:1];
			// we lock around calls to the index, so there is no point
			// in supporting more than one operation simultaneously
	}
	else if ( !useConcurrent && indexQue != nil ) {
		[indexQue cancelAllOperations];
		[indexQue release], indexQue = nil;
	}
}

- (NSMutableData *) storeData {
	[self _flushIndexIfNecessary];
	return storeData;
}

#pragma mark -

+ (void) setDefaultTextAnalysisOption:(id)inObject forKey:(NSString*)inKey {
	[SPSearchStoreTextAnalysisOptions() setObject:inObject forKey:inKey];
}

+ (id) defaultTextAnalysisOptionForKey:(NSString*)inKey {
	return [SPSearchStoreTextAnalysisOptions() objectForKey:inKey];
}

+ (NSSet*) stopWordsForLanguage:(NSString*)inLanguage {
	NSString *words = [SPSearchStoreStopWords() objectForKey:inLanguage];
	return ( words ? [NSSet setWithArray:[words componentsSeparatedByString:@" "]] : nil );
}

#pragma mark -
#pragma mark Document / Store Management

- (BOOL) addDocument:(NSURL*)inDocumentURI withText:(NSString*)inContents {
	
	NSAssert( inDocumentURI!=nil, @"inDocumentURI must not be nil");
	NSAssert( inContents!=nil, @"inContents must not be nil");
	
	// Pass the call to a private method in order to support concurrent processing. Could
	// be made 10.5 compatible using invocation operations or detachNewThreadSelector:
	
	if ( self.usesConcurrentIndexing ) {
		if ( indexQue == nil ) return NO;
		[indexQue addOperationWithBlock:^(void) {
			[self _addDocument:inDocumentURI withText:inContents];
		}];
		return YES;
	}
	else {
		return [self _addDocument:inDocumentURI withText:inContents];
	}
}

- (BOOL) addDocument:(NSURL*)inFileURL typeHint:(NSString*)inMimeHint {
	
	NSAssert( inFileURL!=nil, @"inFileURL must not be nil");
	
	// Pass the call to a private method in order to support concurrent processing. Could
	// be made 10.5 compatible using invocation operations or detachNewThreadSelector:
	
	if ( self.usesConcurrentIndexing ) {
		if ( indexQue == nil ) return NO;
		[indexQue addOperationWithBlock:^(void) {
			[self _addDocument:inFileURL typeHint:inMimeHint];
		}];
		return YES;
	}
	else {
		return [self _addDocument:inFileURL typeHint:inMimeHint];
	}
}

- (BOOL) _addDocument:(NSURL*)inFileURL typeHint:(NSString*)inMimeHint {
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[writeLock lock];
	
	BOOL success = NO;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inFileURL);
	if ( document == NULL ) goto bail; // not always harmful!
	
	success = SKIndexAddDocument(searchIndex, document, (CFStringRef)inMimeHint, true);
	if ( success ) [self _incrementChangeCount];
	
	//
	// CFStringRef name = SKDocumentGetName(document);
	// NSLog(@"name is %@", (NSString*)name);
	//
	
bail:
	if ( document ) CFRelease(document);
	[writeLock unlock];
	[pool release];
	return success;
}

- (BOOL) _addDocument:(NSURL*)inDocumentURI withText:(NSString*)inContents {
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[writeLock lock];
	
	BOOL success = NO;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	success = SKIndexAddDocumentWithText(searchIndex, document, (CFStringRef)inContents, true);
	if ( success ) [self _incrementChangeCount];
	
bail:
	if ( document ) CFRelease(document);
	[writeLock unlock];
	[pool release];
	return success;
}

#pragma mark -

- (BOOL) removeDocument:(NSURL*)inDocumentURI {
	
	NSAssert( inDocumentURI!=nil, @"inFileURL must not be nil");
	
	if ( self.usesConcurrentIndexing ) {
		if ( indexQue == nil ) return NO;
		[indexQue addOperationWithBlock:^(void) {
			[self _removeDocument:inDocumentURI];
		}];
		return YES;
	}
	else {
		return [self _removeDocument:inDocumentURI];
	}

}

- (BOOL) _removeDocument:(NSURL*)inDocumentURI {
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[writeLock lock];
	
	BOOL success = NO;

	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	success = SKIndexRemoveDocument(searchIndex, document);
	if ( success ) [self _incrementChangeCount];

bail:
	if ( document ) CFRelease(document);
	[writeLock unlock];
	[pool release];
	return success;
}

#pragma mark -

- (BOOL) replaceDocument:(NSURL*)oldDocumentURL withDocument:(NSURL*)newDocumentURL typeHint:(NSString*)inMimeHint {
	
	NSAssert( oldDocumentURL!=nil, @"oldDocumentURL must not be nil");
	NSAssert( newDocumentURL!=nil, @"newDocumentURL must not be nil");
	
	if ( self.usesConcurrentIndexing ) {
		if ( indexQue == nil ) return NO;
		[indexQue addOperationWithBlock:^(void) {
			[self _removeDocument:oldDocumentURL];
		}];
		[indexQue addOperationWithBlock:^(void) {
			[self _addDocument:newDocumentURL typeHint:inMimeHint];
		}];
		return YES;
	}
	else {
		BOOL success = [self _removeDocument:oldDocumentURL];
		success = ( success && [self _addDocument:newDocumentURL typeHint:inMimeHint] );
		return success;
	}
}

- (BOOL) replaceDocument:(NSURL*)oldDocumentURI withDocument:(NSURL*)newDocumentURI withText:(NSString*)inContents {
	
	NSAssert( oldDocumentURI!=nil, @"oldDocumentURL must not be nil");
	NSAssert( newDocumentURI!=nil, @"newDocumentURL must not be nil");
	NSAssert( inContents!=nil, @"inContents must not be nil");
	
	if ( self.usesConcurrentIndexing ) {
		if ( indexQue == nil ) return NO;
		[indexQue addOperationWithBlock:^(void) {
			[self _removeDocument:oldDocumentURI];
		}];
		[indexQue addOperationWithBlock:^(void) {
			[self _addDocument:newDocumentURI withText:inContents];
		}];
		return YES;
	}
	else {
		BOOL success = [self _removeDocument:oldDocumentURI];
		success = ( success && [self _addDocument:newDocumentURI withText:inContents] );
		return success;
	}
}

#pragma mark -

- (void) setProperties:(NSDictionary*)inProperties forDocument:(NSURL*)inDocumentURI {
	
	NSAssert( inDocumentURI!=nil, @"inDocumentURI cannot be nil");
	NSAssert( inProperties!=nil, @"inProperties cannot be nil");
	
	[writeLock lock];
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	SKIndexSetDocumentProperties(searchIndex, document, (CFDictionaryRef)inProperties);

bail:
	if ( document ) CFRelease(document);
	[writeLock unlock];
}

- (NSDictionary*) propertiesForDocument:(NSURL*)inDocumentURI {
	
	NSAssert( inDocumentURI!=nil, @"inDocumentURI cannot be nil");
	
	[readLock lock];
	
	CFDictionaryRef properties = NULL;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;

	properties = SKIndexCopyDocumentProperties(searchIndex, document);
	[(id)properties autorelease];
	
bail:
	if ( document ) CFRelease(document);
	[readLock unlock];
	return (NSDictionary*)properties;
}

- (BOOL) setName:(NSString*)inTitle forDocument:(NSURL*)inDocumentURI {
	
	NSAssert( inDocumentURI!=nil, @"inDocumentURI cannot be nil");
	NSAssert( inTitle!=nil, @"inTitle must not be nil");
	
	[writeLock lock];
	
	BOOL success = NO;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	success = SKIndexRenameDocument(searchIndex, document, (CFStringRef)inTitle);
	
bail:
	if ( document ) CFRelease(document);
	[writeLock unlock];
	return success;
}

- (NSString*) nameOfDocument:(NSURL*)inDocumentURI {
		
	NSAssert( inDocumentURI!=nil, @"inDocumentURI cannot be nil");
	
	[readLock lock];
	
	CFStringRef documentName = NULL;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	documentName = SKDocumentGetName(document);
	
bail:
	if ( document ) CFRelease(document);
	[readLock unlock];
	return (NSString*)documentName;
}

- (SKDocumentIndexState) stateOfDocument:(NSURL*)inDocumentURI {
	
	NSAssert( inDocumentURI!=nil, @"inDocumentURI cannot be nil");
	
	[readLock lock];
	
	SKDocumentIndexState documentState = kSKDocumentStateNotIndexed;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	documentState = SKIndexGetDocumentState(searchIndex, document);
	
bail:
	if ( document ) CFRelease(document);
	[readLock unlock];
	return documentState;
}

#pragma mark -

- (NSArray*) allDocuments:(BOOL)ignoreEmptyDocuments {
	
	// There is some curious behavior here regarding the additions SearchKit makes when indexing file 
	// based documents. In addition to indexing the specified file, SearchKit also adds every parent 
	// folder up to a certain (unknown) point. The folders aren't actually indexed, nor their files 
	// which haven't been specified. 
	
	// The SKIndexDocumentIteratorRef will consequently return all of these "documents", even though 
	// none of them were actually added to the index. Fortunately, these documents all have zero terms,
	// so we check for empty documents prior to adding them to our array.
	
	// The trouble with this approach is that indexed documents which have a zero term count will also
	// be filtered by this method.
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	[writeLock lock];
	
	NSArray *allDocuments = [self _allDocumentsForDocumentRef:NULL ignoreEmptyDocuments:ignoreEmptyDocuments];
		// Recursion. Yum.
	
bail:
	[writeLock unlock];
	[readLock unlock];
	return [[allDocuments copy] autorelease];
}

- (NSArray*) _allDocumentsForDocumentRef:(SKDocumentRef)document ignoreEmptyDocuments:(BOOL)ignoresEmpty {
	
	NSMutableArray *allDocuments = [NSMutableArray array];
	
	SKIndexDocumentIteratorRef docIterator = SKIndexDocumentIteratorCreate(searchIndex, document);
	if ( docIterator == NULL ) goto bail;
	
	SKDocumentRef subDocument = SKIndexDocumentIteratorCopyNext(docIterator);
	if ( subDocument == NULL ) goto bail;
	
	while ( subDocument != NULL ) {
		
		CFIndex termCount = 0;
		SKDocumentID subDocumentId = SKIndexGetDocumentID(searchIndex, subDocument);
		if ( subDocumentId != kCFNotFound ) termCount = SKIndexGetDocumentTermCount(searchIndex, subDocumentId);
		
		if ( !( ignoresEmpty && (termCount == 0) ) ) {
		
			CFURLRef subDocumentURL = SKDocumentCopyURL(subDocument);
			if ( subDocumentURL != NULL ) {
				[allDocuments addObject:(NSURL*)subDocumentURL];
				CFRelease(subDocumentURL);
				subDocumentURL = NULL;
			}
		}
		
		NSArray *subDocuments = [self _allDocumentsForDocumentRef:subDocument ignoreEmptyDocuments:ignoresEmpty];
		if ( subDocuments ) [allDocuments addObjectsFromArray:subDocuments];
		
		CFRelease(subDocument);
		subDocument = NULL;
		
		subDocument = SKIndexDocumentIteratorCopyNext(docIterator);
	}
	
bail:
	if ( docIterator ) CFRelease(docIterator);
	return [[allDocuments copy] autorelease];
}

#pragma mark -

- (BOOL) compactStore:(float)tolerance {
	
	BOOL willCompact = NO;
	
	if ( tolerance == 0 ) {
		willCompact = YES;
	}
	else {
		
		SKDocumentID maxDocumentId;
		CFIndex documentCount;
		
		[readLock lock];
		
		documentCount = SKIndexGetDocumentCount(searchIndex);
		maxDocumentId = SKIndexGetMaximumDocumentID(searchIndex);
		
		[readLock unlock];
		
		if ( documentCount > 0 && maxDocumentId > 0 ) {
			
			CFIndex dif = ( maxDocumentId - documentCount );
			willCompact = ( (float)( (float)dif / (float)documentCount ) > tolerance );
		}
	}
	
	if ( willCompact ) {
		if ( indexQue == nil ) {
			indexQue = [[NSOperationQueue alloc] init];
			[indexQue setMaxConcurrentOperationCount:1];
		}
		[indexQue addOperationWithBlock:^(void) {
			[self _compactIndex];
		}];
	}
	
	return willCompact;
}

- (BOOL) saveChangesToStore {
	// This is actually something we do every time a search or term request is made;
	// otherwise the store will not return the correct results. The store is not
	// updated until a search or term request is made, even if there have been multiple
	// documents added, removed or replaced to the store since the last save.
	
	return [self _flushIndexIfNecessary];
}

- (BOOL) closeStore {
	
	BOOL success = NO;
	
	[self cancelSearch];
	
	[readLock lock];
	[writeLock lock];
	
	SKIndexClose(searchIndex);
	searchIndex = NULL;
	
	[writeLock unlock];
	[readLock unlock];
	
	return success;
}

#pragma mark -
#pragma mark Searching

- (void) prepareSearch:(NSString*)searchQuery options:(SKSearchOptions)searchOptions {
	
	NSAssert( searchQuery!=nil, @"searchQuery must not be nil");
	
	if ( [self isStillSearching] )
		[self cancelSearch];
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	
	currentSearch = SKSearchCreate(searchIndex, (CFStringRef)searchQuery, searchOptions);
	if ( currentSearch == NULL ) NSLog(@"there was a problem creating the search query");
	
	[readLock unlock];
}

- (BOOL) fetchResults:(NSArray**)outDocuments ranksArray:(NSArray**)outRanks untilFinished:(BOOL)untilComplete {
	
	// Convenience method to use NSArray for outRanks. May be slower due to Obj-C overhead.
	
	float * ranks = NULL;
	
	BOOL complete = [self fetchResults:outDocuments ranks:(outRanks==NULL?NULL:&ranks) untilFinished:untilComplete];
	
	if ( outRanks != NULL && ranks != NULL ) {
		
		NSUInteger count = [*outDocuments count];
		NSMutableArray *allRanks = [NSMutableArray arrayWithCapacity:count];
		NSInteger i;
		
		for ( i = 0; i < count; i++ ) {
			[allRanks addObject:[NSNumber numberWithFloat:ranks[i] ]];
		}
		
		*outRanks = [[allRanks copy] autorelease];
		free(ranks);
	}
	
	return complete;
}

- (BOOL) fetchResults:(NSArray**)outDocuments ranks:(float**)outRanks untilFinished:(BOOL)untilComplete {
	
	NSAssert( currentSearch!=NULL, @"currentSearch must not be nil, call prepareSearch:options: prior to this method");
	NSAssert( outDocuments!=NULL, @"outDocuments must not be nil");
	
	BOOL stillSearching = YES;
	
	if ( untilComplete ) {
		// fetch the results as many times as is necessary until we have acquired all of it
		NSMutableArray *allDocuments = [NSMutableArray array];
		float * allRanks = NULL;
		CFIndex count = 0;
		NSInteger i;
		
		while ( stillSearching ) {
		
			NSArray * localResults = nil;
			float * localRanks = (outRanks==NULL ? NULL : calloc(self.fetchCount,sizeof(float)) );
			NSInteger localCount = 0;
			
			stillSearching = [self _fetchResults:&localResults ranks:localRanks 
					maxTime:(CFTimeInterval)self.fetchTime 
					maxCount:(CFIndex)self.fetchCount];
			
			localCount = [localResults count];
			count += (CFIndex)localCount;
			
			[allDocuments addObjectsFromArray:localResults];
			if ( outRanks != NULL ) { // I need to keep a growing track of the ranks
				allRanks = reallocf( allRanks, count*sizeof(float) );
				if ( allRanks != NULL ) {
					for ( i = 0; i < localCount; i++ ) {
						allRanks[i+count-localCount] = localRanks[i];
					}
				}
				
				free(localRanks);
				localRanks = NULL;
			}
		}
		
		*outDocuments = [[allDocuments copy] autorelease];
		if ( outRanks != NULL ) *outRanks = allRanks; // caller must free
	}
	else {
		// perform once, simply passing in the parameters we are given
		
		float * localRanks = (outRanks==NULL ? NULL : calloc(self.fetchCount,sizeof(float)) );
		
		stillSearching = [self _fetchResults:outDocuments ranks:localRanks 
				maxTime:(CFTimeInterval)self.fetchTime 
				maxCount:(CFIndex)self.fetchCount];
				
		if ( outRanks != NULL ) *outRanks = localRanks;
	}
	
	if ( stillSearching == NO ) {
		SKSearchCancel(currentSearch);
		CFRelease(currentSearch);
		currentSearch = NULL;
	}
	
	return stillSearching;
}

- (BOOL) _fetchResults:(NSArray**)outDocuments ranks:(float*)outRanks 
		maxTime:(CFTimeInterval)maxTime maxCount:(CFIndex)maxCount {
	
	// outRanks should contain enough memory to hold maxCount floats
	
	CFTimeInterval kMaxTime = maxTime;
	CFIndex kMaxCount = maxCount;
	
	NSMutableArray *documents = [NSMutableArray array];
	BOOL stillSearching = YES;
	NSInteger i;
	
	[readLock lock];
	
	float *documentScores = ( outRanks == NULL ? NULL : calloc(kMaxCount,sizeof(float)) );
	SKDocumentID *documentIds = calloc(kMaxCount,sizeof(SKDocumentID));
	CFURLRef *documentURLs = NULL;
	CFIndex documentCount = 0;
	
	stillSearching = SKSearchFindMatches(currentSearch, kMaxCount, documentIds, 
			documentScores, kMaxTime, &documentCount);
	
	documentURLs = calloc(documentCount, sizeof(CFURLRef));
	
	SKIndexCopyDocumentURLsForDocumentIDs(searchIndex, documentCount, documentIds, documentURLs);
	
	for ( i = 0; i < documentCount; i++ ) {
		if ( outRanks != NULL ) outRanks[i] = documentScores[i];
		[documents addObject:(NSURL*)documentURLs[i]];
		CFRelease(documentURLs[i]);
	}
	
	free(documentScores);
	free(documentURLs);
	free(documentIds);
	
	*outDocuments = [[documents copy] autorelease];
	[readLock unlock];
	return stillSearching;
}

#pragma mark -

- (float*) copyNormalizedRankings:(float*)inRankings {
	
	float maxValue = 0.0;
	NSInteger i; 
	
	NSUInteger count = sizeof(inRankings) / sizeof(float);
	float *normalizedRankings = calloc(count, sizeof(float));
	
	for ( i = 0; i < count; i++ ) {
		if ( inRankings[i] > maxValue ) maxValue = inRankings[i];
	}
	
	for ( i = 0; i < count; i++ ) {
		normalizedRankings[i] = ( maxValue == 0.0 ? 1.0 : inRankings[i] / maxValue );
	}

	return normalizedRankings;
}

- (NSArray*) normalizedRankingsArray:(NSArray*)inRankings {
	
	float maxValue = 0.0;
	NSUInteger count = [inRankings count];
	NSInteger i;
	
	NSMutableArray *normalizedArray = [NSMutableArray arrayWithCapacity:count];
	
	for ( i = 0; i < count; i++ ) {
		float val = [[inRankings objectAtIndex:i] floatValue];
		if ( val > maxValue ) maxValue = val;
	}
	
	for ( i = 0; i < count; i++ ) {
		float val = [[inRankings objectAtIndex:i] floatValue];
		float normalized = ( maxValue == 0.0 ? 1.0 : val / maxValue );
		[normalizedArray addObject:[NSNumber numberWithFloat:normalized]];
	}
	
	return [[normalizedArray copy] autorelease];
}

- (BOOL) isStillSearching {
	BOOL stillSearching;
	
	[readLock lock];
	stillSearching = ( currentSearch != NULL );
	[readLock unlock];
	
	return stillSearching;
}

- (void) cancelSearch {
	[readLock lock];
	
	if ( currentSearch != NULL ) {
		SKSearchCancel(currentSearch);
		CFRelease(currentSearch);
		currentSearch = NULL;
	}
	
	[readLock unlock];
}

#pragma mark -
#pragma mark Document Terms

- (NSArray*) allTerms {
	
	NSAssert( indexType == kSKIndexInvertedVector, @"index must be of type kSKIndexInvertedVector");
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	
	// flush the index before calling - (BOOL) writeIndexToDisk
	NSMutableSet *allTerms = [NSMutableSet set];
	
	CFIndex maxTermID = SKIndexGetMaximumTermID(searchIndex);
	CFIndex aTermID;
	
	for ( aTermID = 0; aTermID < maxTermID; aTermID++ )
	{
		CFIndex documentCount = SKIndexGetTermDocumentCount( searchIndex, aTermID );
		if ( documentCount == 0 ) // may be the case if the index has not been recently flushed
			continue;
		
		CFStringRef aTerm = SKIndexCopyTermStringForTermID( searchIndex, aTermID );
		if ( aTerm == NULL ) {
			NSLog(@"%s - unable to get term for term index %i", __PRETTY_FUNCTION__, aTermID);
			continue;
		}
		
		if ( !( self.ignoresNumericTerms && CFStringGetCharacterAtIndex(aTerm,0) < 0x0041 ) )
			[allTerms addObject:(NSString*)aTerm];
		
		CFRelease(aTerm);
	}
	
	[readLock unlock];
	
	// somewhat annoyingly, SearchKit includes the stop words as document terms
	if ( self.stopWords != nil ) [allTerms minusSet:self.stopWords];
	
	NSArray *termsArray = [allTerms allObjects];
	return termsArray;
}

#pragma mark -

- (NSUInteger) documentCountForTerm:(NSString*)inTerm {
	
	NSAssert( indexType == kSKIndexInvertedVector, @"index must be of type kSKIndexInvertedVector");
	NSAssert( inTerm != nil && [inTerm length] > 0, @"inTerm must not be nil or an empty string" );
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	
	CFIndex documentCount = 0;
	
	// flush the index before calling - (BOOL) writeIndexToDisk
	CFIndex aTermID = SKIndexGetTermIDForTermString( searchIndex, (CFStringRef)inTerm );
	if ( aTermID == kCFNotFound ) goto bail;
	
	documentCount = SKIndexGetTermDocumentCount( searchIndex, aTermID );

bail:
	[readLock unlock];
	return documentCount;
}

- (NSArray*) documentsForTerm:(NSString*)inTerm {
	
	NSAssert( indexType == kSKIndexInvertedVector, @"index must be of type kSKIndexInvertedVector");
	NSAssert( inTerm != nil && [inTerm length] > 0, @"inTerm must not be nil or an empty string" );
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	
	NSMutableArray *documents = [NSMutableArray array];
	
	CFArrayRef documentIdsArray = NULL;
	SKDocumentID *documentIds = NULL;
	CFURLRef *documentURLs = NULL;
	
	CFIndex termId = SKIndexGetTermIDForTermString( searchIndex, (CFStringRef)inTerm );
	if ( termId == kCFNotFound ) goto bail;
	
	CFIndex documentCount = SKIndexGetTermDocumentCount( searchIndex, termId );
	if ( documentCount == 0 ) goto bail;
	
	documentIdsArray = SKIndexCopyDocumentIDArrayForTermID( searchIndex, termId );
	if ( documentIdsArray == NULL ) goto bail;
	
	// I must convert the CFArray to a SKDocumentID * memory block.
	// Annoying. Is there is a better process, or am I cocoa spoiled?
	
	// I don't know why I can't use:
	// CFArrayGetValues(documentIdsArray, CFRangeMake(0,docIdCount), (const void **)documentIds);
	
	CFIndex docIdCount = CFArrayGetCount(documentIdsArray);
	
	documentIds = calloc( docIdCount, sizeof(SKDocumentID) );
	documentURLs = calloc( docIdCount, sizeof(CFURLRef) );
	
	NSInteger i, x = 0;
	for ( i = 0; i < docIdCount; i++ ) {
		SKDocumentID aDocumentId;
		const void * value = CFArrayGetValueAtIndex(documentIdsArray,i);
		if ( CFNumberGetValue( (CFNumberRef)value, kCFNumberSInt32Type, &aDocumentId ) ) {
			documentIds[x++] = aDocumentId;
		}
	}
	
	SKIndexCopyDocumentURLsForDocumentIDs( searchIndex, docIdCount, documentIds, documentURLs);
	
		// On input, a pointer to an array for document URLs (CFURL objects). On output, points to the 
		// previously allocated array, which now contains document URLs corresponding to the document IDs 
		// in inDocumentIDArray. When finished with the document URL array, dispose of it by calling 
		// CFRelease on each array element.
	
	
	for ( i = 0; i < docIdCount; i++ ) {
		[documents addObject:(NSURL*)documentURLs[i]];
		CFRelease(documentURLs[i]);
	}
	
bail:
	if ( documentIdsArray ) CFRelease(documentIdsArray);
	if ( documentURLs ) free(documentURLs);
	if ( documentIds ) free(documentIds);
	[readLock unlock];
	return documents;
}

#pragma mark -

- (NSUInteger) termCountForDocument:(NSURL*)inDocumentURI {
	
	NSAssert( indexType == kSKIndexInvertedVector, @"index must be of type kSKIndexInvertedVector");
	NSAssert( inDocumentURI != nil, @"inDocumentURI must not be nil");
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	
	CFIndex termCount = 0;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	SKDocumentID documentId = SKIndexGetDocumentID(searchIndex, document);
	if ( documentId == kCFNotFound ) goto bail;
		
	termCount = SKIndexGetDocumentTermCount(searchIndex, documentId);
	
bail:	
	if ( document ) CFRelease(document);
	[readLock unlock];
	return termCount;
}

- (NSArray*) termsForDocument:(NSURL*)inDocumentURI {
	
	NSAssert( indexType == kSKIndexInvertedVector, @"index must be of type kSKIndexInvertedVector");
	NSAssert( inDocumentURI != nil, @"inDocumentURI must not be nil");
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	
	NSMutableSet *documentTerms = [NSMutableSet set];
	
	CFArrayRef termIds = NULL;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	SKDocumentID documentId = SKIndexGetDocumentID(searchIndex, document);
	if ( documentId == kCFNotFound ) goto bail;

	termIds = SKIndexCopyTermIDArrayForDocumentID( searchIndex, documentId );
	if ( termIds == NULL ) goto bail;
	
	// convert the termIds to actual terms, by way of these annoying get values method again
	
	CFIndex termCount = CFArrayGetCount(termIds);
	NSInteger i;
	
	for ( i = 0; i < termCount; i++ ) {
		
		CFNumberRef aNumberRef = CFArrayGetValueAtIndex(termIds,i);
		CFIndex aTermId;
		
		if ( !CFNumberGetValue( aNumberRef, kCFNumberSInt32Type, &aTermId) )
			continue; 
		
		CFIndex documentCount = SKIndexGetTermDocumentCount( searchIndex, aTermId );
		if ( documentCount == 0 ) // if the index has not been compacted
			continue;
		
		CFStringRef aTerm = SKIndexCopyTermStringForTermID( searchIndex, aTermId );
		if ( aTerm == NULL ) 
			continue;
		
		if ( !( self.ignoresNumericTerms && CFStringGetCharacterAtIndex(aTerm,0) < 0x0041 ) )
			[documentTerms addObject:(NSString*)aTerm];
		
		CFRelease(aTerm);
	}
	
bail:
	if ( document ) CFRelease(document);
	if ( termIds ) CFRelease(termIds);
	[readLock unlock];
	
	if ( self.stopWords != nil ) [documentTerms minusSet:self.stopWords];
	
	NSArray *termsArray = [documentTerms allObjects];
	return termsArray;
}

- (NSUInteger) frequencyOfTerm:(NSString*)inTerm inDocument:(NSURL*)inDocumentURI {
	
	NSAssert( indexType == kSKIndexInvertedVector, @"index must be of type kSKIndexInvertedVector");
	NSAssert( inTerm != nil && [inTerm length] > 0, @"inTerm must not be nil or an empty string" );
	NSAssert( inDocumentURI != nil, @"inDocumentURI must not be nil");
	
	[self _flushIndexIfNecessary];
	[readLock lock];
	
	CFIndex termCount = 0;
	
	SKDocumentRef document = SKDocumentCreateWithURL((CFURLRef)inDocumentURI);
	if ( document == NULL ) goto bail;
	
	SKDocumentID documentId = SKIndexGetDocumentID(searchIndex, document);
	if ( documentId == kCFNotFound ) goto bail;
	
	CFIndex termId = SKIndexGetTermIDForTermString( searchIndex, (CFStringRef)inTerm );
	if ( termId == kCFNotFound ) goto bail;
	
	termCount = SKIndexGetDocumentTermFrequency( searchIndex, documentId, termId);
	
bail:
	if ( document ) CFRelease(document);
	[readLock unlock];
	return termCount;
}

#pragma mark -
#pragma mark Utilities

- (void) _incrementChangeCount {
	changeCount++;
}

- (BOOL) _flushIndexIfNecessary {
	if ( changeCount == 0 ) 
		return YES;
	
	// Before searching an index, always call SKIndexFlush, even though the flush process may take up to 
	// several seconds. If there are no updates to commit, a call to SKIndexFlush does nothing 
	// and takes minimal time.
	
	BOOL success = NO;
	[writeLock lock];
	
	success = SKIndexFlush(searchIndex);
	if ( success ) changeCount = 0;
	
	[writeLock unlock];
	
	return success;
}

- (BOOL) _compactIndex {
	
	// To check for bloat you can take advantage of the way Search Kit assigns document IDs. 
	// It does so starting at 1 and without reusing previously allocated IDs for an index. 
	// Simply compare the highest document ID, found with the SKIndexGetMaximumDocumentID() function, 
	// with the current document count, found with the SKIndexGetDocumentCount() function.
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL success = NO;
	
	[readLock lock];
	[writeLock lock];
	
	success = SKIndexCompact(searchIndex);
	
	[writeLock unlock];
	[readLock unlock];
	
	[pool release];
	return success;
}

@end
