//
//  SPSearchStoreAppDelegate.m
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

#import "SPSearchStoreAppDelegate.h"
#import "SPSearchStore.h"

@implementation SPSearchStoreAppDelegate

@synthesize window;

@synthesize documentsTable;
@synthesize termsTable;
@synthesize containingTable;

#pragma mark -

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// Insert code here to initialize your application 
	
	/* Initializes our data model to display the document <-> term relationships */
	
	fm = [[NSFileManager alloc] init];
	documents = [[NSMutableSet alloc] init];
	
	filteredDocuments = [[NSMutableArray alloc] init];
	terms = [[NSMutableArray alloc] init];
	containing = [[NSMutableArray alloc] init];
	
	NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:@"path" ascending:YES];
	descriptors = [[NSArray arrayWithObject:descriptor] retain];
	
	
	/* Initialize the store */
	
	[self initializeStoreWithData:nil];
	
	// Comment out the above line and uncomment the following lines to test with a 
	// file-based store. The openDocument and saveDocument methods will not work. 
	// You should also uncomment the saveChangesToStore call in the 
	// applicationWillTerminate method beloew.
	
	// NSString *path = [@"~/spsearchstore.index" stringByExpandingTildeInPath];
	// NSURL *url = [NSURL fileURLWithPath:path];
	
	// [self initializeStoreWithURL:url];
}

- (void) applicationWillTerminate:(NSNotification *)aNotification {
	
	// Close out the store before your document or application shuts down, whether
	// you are in a garbage collected environment or not.
	
	// We would uncomment the following line if we also wanted to guarantee that 
	// changes to the store have been written to the memory or disk backing.
	
	// [searchStore saveChangesToStore];													// <- call to store
	
	[searchStore closeStore];																//
}

- (void) initializeStoreWithData:(NSMutableData*)inData {									// <- call to store
																							//		...
	/* Begin store initialization */
	
	// Initialize the search store. Before we create the search store we specify some
	// default text analysis options we would like to use.
	
	[SPSearchStore setDefaultTextAnalysisOption:[SPSearchStore stopWordsForLanguage:@"en"] 
			forKey:(NSString *)kSKStopWords];
			
	[SPSearchStore setDefaultTextAnalysisOption:[NSNumber numberWithBool:YES] 
			forKey:(NSString *)kSKProximityIndexing];
			
	[SPSearchStore setDefaultTextAnalysisOption:[NSNumber numberWithInteger:2] 
			forKey:(NSString *)kSKMinTermLength];
	
	// We are creating an in-memory search store. File based stores are great too.
	// If we wanted to persist our in-memory store we could grab the storeData from
	// searchStore after adding documents to it and write it out to a file or other store.
	// I do exactly this in the saveDocuemnt method below
	
	searchStore = [[SPSearchStore alloc] initStoreWithMemory:inData type:kSKIndexInvertedVector];
	if ( searchStore == nil ) NSLog(@"There was a problem creating the search store");
	
	searchStore.usesSpotlightImporters = YES;
	searchStore.usesConcurrentIndexing = YES;
	searchStore.ignoresNumericTerms = YES;
	
	/* Store initialization is complete at this point */
}

- (void) initializeStoreWithURL:(NSURL*)inFileURL {											// <- call to store
																							//		...
	// Refer to above method for an explanation...
	
	[SPSearchStore setDefaultTextAnalysisOption:[SPSearchStore stopWordsForLanguage:@"en"] 
			forKey:(NSString *)kSKStopWords];
			
	[SPSearchStore setDefaultTextAnalysisOption:[NSNumber numberWithBool:YES] 
			forKey:(NSString *)kSKProximityIndexing];
			
	[SPSearchStore setDefaultTextAnalysisOption:[NSNumber numberWithInteger:2] 
			forKey:(NSString *)kSKMinTermLength];
	
	searchStore = [[SPSearchStore alloc] initStoreWithURL:inFileURL type:kSKIndexInvertedVector];
	if ( searchStore == nil ) NSLog(@"There was a problem creating the search store");
	
	searchStore.usesSpotlightImporters = YES;
	searchStore.usesConcurrentIndexing = YES;
	searchStore.ignoresNumericTerms = YES;
	
	if ( searchStore.didCreateStore == NO ) { 
		
		[searchStore compactStore:0.25];
		
		// This is a good time to compact the store if necessary, but this function
		// will block any other calls to the store. Usually that will not matter;
		// it matters to us because we immediately call allDocuments on the store,
		// as we do not otherwise keep track of the documents indexed.
		
		[documents removeAllObjects];
		[documents addObjectsFromArray:[searchStore allDocuments:YES]];
		
		[self reloadDocumentsTableWithAllDocuments];
	}
}

#pragma mark -

- (IBAction) addDocuments:(id)sender {
	
	NSOpenPanel *op = [NSOpenPanel openPanel];
	
	[op setAllowsMultipleSelection:YES];
	[op setCanChooseDirectories:NO];
	[op setCanChooseFiles:YES];
	
	[op beginWithCompletionHandler:^(NSInteger result) {
		
		if ( result == NSFileHandlingPanelOKButton ) {
			
			NSArray *selection = [op URLs];
			[selection enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				
				// add the document to the store
				[searchStore addDocument:(NSURL*)obj typeHint:nil];							// <- call to store
				
				// add the document to our model
				[documents addObject:(NSURL*)obj];
			}];
		}
		
		[self reloadDocumentsTableWithAllDocuments];
		
	}];
}

- (IBAction) removeDocument:(id)sender {
	
	NSInteger selectedRow = [documentsTable selectedRow];
	if ( selectedRow == -1 ) {
		NSBeep(); return;
	}
	
	NSURL *documentURL = [[filteredDocuments objectAtIndex:selectedRow] retain];
	
	[filteredDocuments removeObject:documentURL];
	[documents removeObject:documentURL];
	
	[searchStore removeDocument:documentURL];												// <- call to store
	
	[documentURL release];
	
	[documentsTable deselectAll:self];
	[documentsTable reloadData];
}

- (IBAction) reloadDocument:(id)sender {
	
	// Reloading a document is a simple affair: just add it back to the index.
	// However, if the document's location has changed you should replace it.
	
	NSInteger selectedRow = [documentsTable selectedRow];
	if ( selectedRow == -1 ) {
		NSBeep(); return;
	}
	
	NSURL *documentURL = [[filteredDocuments objectAtIndex:selectedRow] retain];
	
	[searchStore addDocument:documentURL typeHint:nil];										// <- call to store

	// Fake a selection change in order to reload the document's terms
	
	[[NSNotificationCenter defaultCenter] 
			postNotificationName:NSTableViewSelectionDidChangeNotification 
			object:documentsTable];
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem {
	
	SEL action = [menuItem action];
	BOOL enabled = YES;
	
	if ( action == @selector(removeDocument:) || action == @selector(reloadDocument:) )
		enabled = ( [documentsTable selectedRow] != -1 );
	
	return enabled;
}

#pragma mark -

- (void) reloadDocumentsTableWithAllDocuments {
	
	[filteredDocuments removeAllObjects];
	[filteredDocuments addObjectsFromArray:[[documents allObjects] 
			sortedArrayUsingDescriptors:descriptors]];
	
	[documentsTable deselectAll:self];
	[documentsTable reloadData];
	
	[[[documentsTable tableColumnWithIdentifier:@"main"] headerCell] setStringValue:
			[NSString stringWithFormat:@"Documents: %i",[filteredDocuments count]]];
	
	
	// Don't care for the rest of the interface? Just uncomment the lines below and
	// see what happens when you load documents into the store.
	
	/*
	NSArray *terms = [searchStore allTerms];
	NSLog(@"%@", terms);
	
	NSString *term = [terms objectAtIndex:0];
	NSArray *docs = [searchStore documentsForTerm:term];
	NSLog(@"%@ occurs in %@", term, docs);
	
	NSURL *docURI = [docs objectAtIndex:0];
	NSArray *docTerms = [searchStore termsForDocument:docURI];
	
	NSLog(@"%@ has the terms %@", docURI, docTerms);
	
	NSArray * results = nil;
	NSArray * normalizedRanks = nil;
	NSArray * ranks = nil;
	
	[searchStore prepareSearch:term options:kSKSearchOptionDefault];
	[searchStore fetchResults:&results ranksArray:&ranks untilFinished:YES];
	
	normalizedRanks = [searchStore normalizedRankingsArray:ranks];
	
	NSLog(@"%@ returns %@ with ranks %@", term, results, normalizedRanks);
	
	NSArray *allDocs = [searchStore allDocuments];
	NSLog(@"all documents: %@", allDocs);
	*/
}

- (void) updateDocumentsTableWithSearchResults:(NSArray*)searchResults {
	
	[filteredDocuments removeAllObjects];
	[filteredDocuments addObjectsFromArray:[searchResults sortedArrayUsingDescriptors:descriptors]];

	[documentsTable deselectAll:self];
	[documentsTable reloadData];
	
	[[[documentsTable tableColumnWithIdentifier:@"main"] headerCell] setStringValue:
			[NSString stringWithFormat:@"Documents: %i / %i ",
			[filteredDocuments count], [documents count]]];
}

#pragma mark -

- (IBAction) performSearch:(id)sender {
	
	static NSInteger kMinTermLength = 2;
	
	// Search options:
	//	kSKSearchOptionDefault
	//	kSKSearchOptionNoRelevanceScores
	//	kSKSearchOptionSpaceMeansOR
	//	kSKSearchOptionFindSimilar
	
	// See the SPSearchStore fetchResults:ranksArray:untilFinished: header definition
	// for more information on SearchKit queries.
	
	// We perform a very basic, single threaded search here that may potentially block the
	// interface if the index is adequately large. (Actually, SearchKit spawns a thread
	// for the query but we block the main thread during fetch). A more advanced search
	// might launch a separate operation or thread to perform the search and fetch, and
	// then cancel that operation prior to performing any more searches.
		
	NSString *searchValue = [sender stringValue];
	
	if ( [searchValue length] < kMinTermLength ) {
		// reset the documents array
		[self reloadDocumentsTableWithAllDocuments];
		return;
	}
	
	NSArray *results = nil;
	NSArray *rankings = nil;
	NSArray *normalizedRankings = nil;
	
	[searchStore cancelSearch];																// <- call to store
	[searchStore prepareSearch:searchValue options:kSKSearchOptionDefault];					//
	[searchStore fetchResults:&results ranksArray:&rankings untilFinished:YES];				//
		
	normalizedRankings = [searchStore normalizedRankingsArray:rankings];					//
		// we aren't using the normalized rankings, but you should call 
		// this method if you are
	
	[self updateDocumentsTableWithSearchResults:results];
}

- (IBAction) performConcurrentSearch:(id)sender {

	if ( searchQue == nil ) {
		searchQue = [[NSOperationQueue alloc] init];
		[searchQue setMaxConcurrentOperationCount:1];
	}
	
	// This is a more advanced, concurrent search which performs both query preparation and
	// result fetching in a non-blocking manner. We use a serial operation queue to permit
	// a single search query to take place at a time. During the processing, we check if this
	// query is still the active one, and if not, we end it, allowing the next, more current
	// search operation to begin.
	
	// We check if the active query is the current one by comparing a local copy of the query
	// string to the current string. Objective-C exceptions must be enabled for this 
	// particular implementation to work.
	
	// I imagine there are better ways to accomplish this. Concurrency programming is not my
	// forte, and suggestions for improvements are gladly accepted. 
	
	static NSInteger kMinTermLength = 2;
	
	@synchronized(searchString) {
		// Lock here. If an operation block is currently in the middle of a fetch, when it
		// finishes the fetch and checks its local searchString copy against this one, it
		// will bail on the operation.
		
		// On the other hand, if the operation block is in the middle of updating the UI, we
		// want to allow that process to finish so that we can then immediately force the UI 
		// back to a clean state with a call to reloadDocumentsTableWithAllDocuments.
				
		[searchString release], searchString = nil;
		searchString = [[sender stringValue] copy];
	}
	
	if ( [searchString length] < kMinTermLength ) {
		[searchString release], searchString = nil;
		// reset the documents array
		[self reloadDocumentsTableWithAllDocuments];
		return;
	}
	
	[searchQue addOperationWithBlock:^(void) {
		
		NSString *blockSearchValue = nil;
		BOOL stillSearching = YES;
		
		NSMutableArray *results = [NSMutableArray array];
		NSMutableArray *rankings = [NSMutableArray array];
		NSArray *normalizedRankings = nil;
		
		@synchronized(searchString) {
			blockSearchValue = [searchString copy];
		}
		
		[searchStore cancelSearch];															// <- call to store
		[searchStore prepareSearch:blockSearchValue options:kSKSearchOptionDefault];		//
		
		while ( stillSearching ) {
			
			NSArray *localResults = nil;
			NSArray *localRankings = nil;
			
			@synchronized(searchString) {
				
				// check the current state of the search prior to each fetch iteration
				if ( ![blockSearchValue isEqualToString:searchString] ) {
					[blockSearchValue release], blockSearchValue = nil;
					[searchStore cancelSearch];												// <- call to store
					return; // exit the block
				}
			}
			
			// the fetch will return even if we haven't acquired all the results
			stillSearching = [searchStore fetchResults:&localResults						// <- call to store
					ranksArray:&localRankings untilFinished:NO];
			
			[rankings addObjectsFromArray:localRankings];
			[results addObjectsFromArray:localResults];
			
			// optionally, we could update the UI here each time we have acquired
			// new results, instead of waiting until we are finished searching.
		}
		
		@synchronized(searchString) {
			// check the current state of the search one last time before updating
			// the user interface; lock the code until we've finished updating the UI
			
			if ( ![blockSearchValue isEqualToString:searchString] ) {
				[blockSearchValue release], blockSearchValue = nil;
				[searchStore cancelSearch];													// <- call to store
				return; // exit the block
			}
			
			normalizedRankings = [searchStore normalizedRankingsArray:rankings];
				// we aren't using the normalized rankings, but you should call 
				// this method if you are
			
			// always update the UI on the main thread
			[self performSelectorOnMainThread:@selector(updateDocumentsTableWithSearchResults:) 
					withObject:results waitUntilDone:YES];
								
			[blockSearchValue release]; 
			blockSearchValue = nil;
		}
	}];
}

#pragma mark -

- (IBAction) saveDocument:(id)sender {
	
	// Write the store data to disk. Because we have a memory based store, first we flush 
	// the index to the memory backing and then we write out the data object. If this were 
	// a file based store, we could simply call saveChangesToStore
	
	NSData *storeData = nil;
	
	[searchStore saveChangesToStore];														// <- call to store
	storeData = [searchStore storeData];													//
	
	NSSavePanel *sp = [NSSavePanel savePanel];
	
	[sp setAllowedFileTypes:[NSArray arrayWithObject:@"spmstore"]];
	
	[sp beginWithCompletionHandler:^(NSInteger result) {
		
		if ( result != NSFileHandlingPanelOKButton )
			return;
		
		NSURL *fileURL = [sp URL];
		NSError *error = nil;
		
		[storeData writeToURL:fileURL options:NSDataWritingAtomic error:&error];
	}];
}

- (IBAction) openDocument:(id)sender {
	
	// Ask for a document of type .spmstore and if we have one, clean out the current
	// store and replace it with the new store. Note that we reload our indexed documents
	// from the store itself, whereas typically an application will maintain an object
	// graph which keeps track of these files independently of the store.
	
	NSOpenPanel *op = [NSOpenPanel openPanel];
	
	[op setAllowedFileTypes:[NSArray arrayWithObject:@"spmstore"]];
	[op setAllowsMultipleSelection:NO];
	
	[op beginWithCompletionHandler:^(NSInteger result) {
		
		if ( result != NSFileHandlingPanelOKButton )
			return;
		
		NSURL *fileURL = [op URL];
		NSError *error = nil;
		
		NSMutableData *storeData = [NSMutableData dataWithContentsOfURL:fileURL options:0 error:&error];
		if ( storeData != nil ) {
			
			[searchStore release];
			searchStore = nil;
			
			[self initializeStoreWithData:storeData];
			
			if ( searchStore != nil ) {
				// reload our local documents url array from the store
				NSArray *loadedDocs = [searchStore allDocuments:YES];							// <- call to store
					
					// see the header declaration for the allDocuments method
					// for details on why this call may not return the results
					// you expect
				
				[documents removeAllObjects];
				[documents addObjectsFromArray:loadedDocs]; 
				[self reloadDocumentsTableWithAllDocuments];
				
				// After loading a saved store you have a good opportunity to check for
				// index bloat. Check to compact the index here. Note that we check
				// after calling allDocuments on the store because this method, although
				// it is performed on a separate thread, will block all other store
				// queries and alterations, including the call to allDocuments.
				
				[searchStore compactStore:0.25];											// <- call to store
			}
		}
		
	}];
	
}

#pragma mark -
#pragma mark Table View Data Source & Delegateion

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
	
	if ( aTableView == documentsTable )
	{
		return [filteredDocuments count];
	}
	else if ( aTableView == termsTable )
	{
		return [terms count];
	}
	else if ( aTableView == containingTable )
	{
		return [containing count];
	}
	
	return 0;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn 
		row:(NSInteger)rowIndex {
	
	if ( aTableView == documentsTable )
	{
		return [fm displayNameAtPath:[[filteredDocuments objectAtIndex:rowIndex] path]];
	}
	else if ( aTableView == termsTable )
	{
		return [terms objectAtIndex:rowIndex];
	}
	else if ( aTableView == containingTable )
	{
		return [fm displayNameAtPath:[[containing objectAtIndex:rowIndex] path]];
	}
	
	return nil;
}

#pragma mark -

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	NSTableView *aTableView = [aNotification object];
	NSInteger rowIndex = [aTableView selectedRow];
	
	if ( aTableView == documentsTable )
	{
		[termsTable deselectAll:self];
		[terms removeAllObjects];
		
		if ( rowIndex != -1 ) {
			
			NSURL *documentURL = [filteredDocuments objectAtIndex:rowIndex];
			NSArray *documentTerms = [searchStore termsForDocument:documentURL];			// <- call to store
			
			[terms addObjectsFromArray:[documentTerms sortedArrayUsingSelector:
					@selector(caseInsensitiveCompare:)]];
		}
		
		[termsTable reloadData];
		
		[[[termsTable tableColumnWithIdentifier:@"main"] headerCell] setStringValue:
				[NSString stringWithFormat:@"Document Terms: %i",[terms count]]];
		
	}
	else if ( aTableView == termsTable )
	{
		[containing removeAllObjects];
		
		if ( rowIndex != -1 ) {
			
			NSString *term = [terms objectAtIndex:rowIndex];
			NSArray *containgDocuments = [searchStore documentsForTerm:term];				// <- call to store
			
			[containing addObjectsFromArray:[containgDocuments 
					sortedArrayUsingDescriptors:descriptors]];
		}
		
		[containingTable reloadData];
		
		[[[containingTable tableColumnWithIdentifier:@"main"] headerCell] setStringValue:
				[NSString stringWithFormat:@"Docs Containing Term: %i",[containing count]]];
	}
}

@end
