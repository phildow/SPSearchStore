//
//  SPSearchStore.h
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

#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>

// Be sure to link to Core/Services

@interface SPSearchStore : NSObject {
	
	SKIndexRef searchIndex;
	SKIndexType indexType;
	
	NSMutableData *storeData;
	NSURL *storeURL;
	BOOL didCreateStore;
	
	NSOperationQueue *indexQue;
	NSLock *writeLock;
	NSLock *readLock;
	
	// Should we use NSRecursiveLock instead? Docs:
	// "Recursive locks are used during recursive iterations primarily but may also be used in cases where
	//  multiple methods each need to acquire the lock separately."
	
	// Docs: "Search Kit is thread-safe. You can use separate indexing and searching threads. Your application 
	// is responsible for ensuring that no more than one process is open at a time for writing to an index."
	// We ensure that here by using separate locks for reading and writing. Your classes do not need to
	// worry about threaded access.
	
	NSDictionary *analysisOptions;
	NSSet *stopWords;
	
	BOOL usesSpotlightImporters;
	BOOL usesConcurrentIndexing;
	BOOL ignoresNumericTerms;
	
	NSTimeInterval fetchTime;
	NSInteger fetchCount;
	
	SKSearchRef currentSearch;
	NSUInteger changeCount;
}

@property (readonly) SKIndexRef searchIndex;
	
	// In case you want direct access to the SKIndexRef used by SPSearchStore. If your 
	// application is multi-threaded, take care to control access to the store. When you
	// use this class to access the store, multi-threading issues are managed automatically.

@property (readonly,retain) NSLock *writeLock;
@property (readonly,retain) NSLock *readLock;

	// If you are directly accessing the SKIndexRef searchIndex you must ensure that you do not
	// perform more than one indexing and more than one searching operation simultaneously.
	// You may use these locks to control access to the index.

@property (readonly,retain) NSMutableData *storeData;	

	// The storeData property only applies to stores created in memory and will be nil
	// for file based stores. You can use this data object to persist your store.

@property (readonly,retain) NSURL *storeURL;
	
	// The storeURL property applies only to disk based stores and will be nil for in-
	// memory stores. It is equal to the URL provided during store initialization or to
	// the URL representation of the filepath string.

@property (readonly) BOOL didCreateStore;

	// The didCreateStore property only applies to disk based stores and will be YES if 
	// SearchKit created a store at the file URL specified during store creation, NO 
	// otherwise. You can check this value when you initialize a file based store from a
	// saved URL to see if the file still existed. If not, you might use the opportunity
	// to rebuild the search index.

@property (readwrite) BOOL usesSpotlightImporters;

	// This calls the SKLoadDefaultExtractorPlugIns search kit method. You should only
	// call this accessor once and prior to loading any file based data into your store.
	
@property (readwrite) BOOL usesConcurrentIndexing;

	// Indexing will occur on a thread separate from the main thread. Only one item will
	// be added to the search index at a time, but batch document indexing will not
	// stall the UI during processing.
	
@property (readwrite) BOOL ignoresNumericTerms;
	
	// SearchKit text analysis options include support for a kSKTermChars and kSKStartTermChars
	// value, but they are used to specify valid word characters in addition to the default
	// alphanumeric characters. If you want to ignore numeric "words" in your results,
	// set this value to YES. Numeric words are still indexed, but they will not be included
	// in term (and search?) results.

@property (readonly,copy) NSDictionary *analysisOptions;

	// The analysisOptions currently in use by the store, including stop words, minimum term
	// length, starting characters and other options you specified prior to store creation.
	
@property (readwrite) NSTimeInterval fetchTime;
@property (readwrite) NSInteger fetchCount;

	// SearchKit allows you specify the maximum amount of time or the maximum number of results 
	// an individual SKSearchFindMatches / fetch operation should take or return. You may set these
	// values to suit your needs. The default fetchTime is 0.5 seconds and the default fetchCount 
	// is 100. This does not place an upper limit on the total number of results which will be
	// returned, only a limit on the results captured in any one chunk. Refer to the fetchResults:
	// method below for more information.
	
#pragma mark -

- (id) initStoreWithMemory:(NSMutableData*)inData type:(SKIndexType)inType;
- (id) initStoreWithFilename:(NSString*)inPath type:(SKIndexType)inType;
- (id) initStoreWithURL:(NSURL*)inFileURL type:(SKIndexType)inType;

	// Refer to the SearchKit documentation on SKIndexType to determine the best type
	// for your needs. Search kit supports mapping documents to terms, terms to documents
	// and both. kSKIndexInvertedVector specifies two way document <-> term matching
	// and is the most comprehensive type. You must specify this type to use the advanced
	// term support of this class.
	
#pragma mark -
	
+ (void) setDefaultTextAnalysisOption:(id)inObject forKey:(NSString*)inKey;
+ (id) defaultTextAnalysisOptionForKey:(NSString*)inKey;

	// Call the set method any number of times prior to initializng your SPSearchStore. 
	// The compiled key/value pairs will be used when creating the index and specify
	// language analysis preferences such as stop words, term length and proximity indexing.
	// See the SearchKit documentation for a complete listing of the analysis options.
	
	// If you do not call this method prior to creating a search store, a bare set of default 
	// values will be used: no proximity indexing, minimum term length of one, no stop words 
	// and no maximum terms for a document (whereas the default is 2000).
	
+ (NSSet*) stopWordsForLanguage:(NSString*)inLanguage;

	// Stop words are short, common words such as articles, prepositions and conjunctions
	// which have little semantic value and are generally avoided by search indexes.
	// SearchKit does not include built-in sets of stop words, so this class attempts
	// to provide default values. You must specify the default stop words and other 
	// analysis preferences prior to the creation of your index using the method above.
	
	// inLanguage is a two-character language specifier such as "en" or "de". Currently
	// this method only returns stop words for the English language. You may expand 
	// stop word support by modifying the SPSearchStoreStopWords() function in the class
	// file.	

#pragma mark -
#pragma mark Index / Document Management

- (BOOL) addDocument:(NSURL*)inFileURL typeHint:(NSString*)inMimeHint;
- (BOOL) addDocument:(NSURL*)inDocumentURI withText:(NSString*)inContents;

	// These two methods form the core of document indexing. You can index two kinds of content:
	// 1. file based content and 2. free-standing text content.
	
	// When you index file based content you must provide the url of the local file. You may
	// also provide a mime type hint which can help SearchKit determine which text importer
	// to use when indexing the file. inMimeHint may be nil.
	
	// When you index free-standing text you must provide some kind of resource identifier
	// which tells SearchKit how to refer to that content. For example, if you maintain a core 
	// data store, you can use a custom uri format to refer to your objects in a persistent 
	// manner, such as myapp://entry/xid, where xid is an attribute by which you can re-fetch 
	// that entry object.
	
	// Returns YES if the document was successfully indexed, no otherwise; however, the return
	// value is always YES if you have set usesConcurrentIndexing.

- (BOOL) removeDocument:(NSURL*)inDocumentURI;

	// Use a single method to remove a document from the search index. If it is a file, simply
	// pass the same file URL you provided to the addDocument method. If it is free-standing
	// text content, use the same document URI previously used.
	
	// Returns YES if the document was successfully removed, no otherwise; however, the return
	// value is always YES if you have set usesConcurrentIndexing.
	
- (BOOL) replaceDocument:(NSURL*)oldDocumentURL withDocument:(NSURL*)newDocumentURL typeHint:(NSString*)inMimeHint;
- (BOOL) replaceDocument:(NSURL*)oldDocumentURI withDocument:(NSURL*)newDocumentURI withText:(NSString*)inContents;

	// These are convenience methods for updating the search index when either 1. a document's 
	// file url has changed or 2. the content uri has changed. Normally you can simply add a 
	// changed document to the index, and the old indexing is replaced. When the document's uri
	// changes, however, you must remove it from the store first, providing the old location, or
	// else you will end up with orphaned content.
	
	// More succinctly: use these methods when a document's location changes.

- (void) setProperties:(NSDictionary*)inProperties forDocument:(NSURL*)inDocumentURI;
- (NSDictionary*) propertiesForDocument:(NSURL*)inDocumentURI;

	// SearchKit supports the association of arbitrary key-value pairs with the documents it keeps
	// in an index. Use these methods to store and retrieve document specific metadata with
	// the index. You may pass file or custom urls to inDocumentURI. 

- (BOOL) setName:(NSString*)inTitle forDocument:(NSURL*)inDocumentURI;
- (NSString*) nameOfDocument:(NSURL*)inDocumentURI;

	// Changes the name of a file based or free standing text document. Return YES if the operation
	// was successful.
	
	// Returns the name of a file based or free standing text document. Returns nil if there is no
	// name or if the operation is not successful.

- (SKDocumentIndexState) stateOfDocument:(NSURL*)inDocumentURI;

	// Docs: "A document URL object (SKDocumentRef) can be in one of four states, as defined by the 
	// SKDocumentIndexState enumeration: not indexed, indexed, not in the index but will be added 
	// after the index is flushed or closed, and in the index but will be deleted after the index is 
	// flushed or closed."

- (NSArray*) allDocuments:(BOOL)ignoreEmptyDocuments;

	// Returns all the documents currently indexed in the search store. If ignoreEmptyDocuments is YES,
	// documents with a term count of zero will not be returned, so that the count may not match a 
	// separate call to SKIndexGetDocumentCount().
	
	// When ignoreEmptyDocuments is YES, this method may not return every document you have added to 
	// the store. When ignoreEmptyDocuments is NO, this method may return "documents" which you have 
	// not explicitly added to the store. See the implementation for details on native SearchKit 
	// behavior and why this method may return unexpected results.
	
	// Generally you should maintain a separate account of the documents you add to a store and set
	// ignoreEmptyDocuments to YES, or not use this method at all.
	
#pragma mark -

- (BOOL) compactStore:(float)tolerance;

	// Over time an index becomes bloated with orphaned terms whose associated documents have been
	// removed but which are themselves left behind. Compacting an index removes these orphaned terms.
	// You should call this method from time to time. One option is to call it anytime you initialize 
	// a previously saved store. SPSearchStore will check for bloat and compact the index if necessary, 
	// taking into account the tolerance value you specify. Returns YES when compacting is required.
	
	// tolerance should be between 0 and 1. Pass a value of 0 to force this method to compact the index.
	
	// Because index compacting is potentially an expensive operation, SPSearchStore always performs
	// the operation on a separate thread. Indexing and querying are unavailable during this time, and
	// any calls to index or query the store will block that thread until compaction is completed.

- (BOOL) saveChangesToStore;
	
	// This updates the index store backing. For an in-memory store it updates the storeData object
	// and for on-disk stores is writes out the index to the filesystem. SPSearchStore manages the
	// store state as needed by your search and term requests, but you may save the store at any
	// time by calling this method.
	
- (BOOL) closeStore;

	// Cancels any active search and closes access to the index. This method does not update the store
	// backing. Call saveChangesToStore if you also want to save changes to the search index.
	
	// You will usually want to call this method immediately prior to your application shutting down
	// or the closing of a document. You should call this method in both managed and garbage 
	// collecting environments.

#pragma mark -
#pragma mark Searching

- (void) prepareSearch:(NSString*)searchQuery options:(SKSearchOptions)searchOptions;
- (BOOL) fetchResults:(NSArray**)outDocuments ranks:(float**)outRanks untilFinished:(BOOL)untilComplete;
- (BOOL) fetchResults:(NSArray**)outDocuments ranksArray:(NSArray**)outRanks untilFinished:(BOOL)untilComplete;
	
	// SearchKit uses a two stage pattern to perform searching, and that process is mirrored by this
	// class. The first stage initializes the search from a query / options combination and starts the 
	// search running on a separate thread. The second stage consists of potentially multiple calls to 
	// the index asking for chunks of the search results.
	
	// Use these two methods to perform a search. First prepare the search using a query string and 
	// search options, then submit mutliple calls to fetchResults. That method will return YES until the 
	// search query is exhausted, at which point it will return NO and clean up the operation. You may
	// cancel the query at any prior point using the cancelSearch method below.
	
	// If you would prefer to make a single call to fetchResults you may set the untilComplete flag to
	// YES. If you perform this method on its own separate thread in order to prevent blocking of the
	// UI, you should call cancelSearch before preparing another query, for example, if the user changes 
	// the query string before the current search returns.
	
	// outRanks should be a pointer to an array of float values, or NULL. Because the size of the array
	// is not determined beforehand, the memory will be allocated and returned to the caller. You must
	// call free() on the value to release the memory. outDocuments is an autoreleased NSArray. The
	// number of floats in outRanks is equal to the count of outDocuments.
	
	// If you do not want to bother with the managing of C float pointers you may use the second of the
	// fetchResults functions which takes an NSArray paramater for the outRanks value. This is a 
	// convenience method that is otherwise functionally the same. It will, however, be slower, due to 
	// the objective-c runtime overhead necessary to wrap float values in NSNumber objects. The impact
	// may or may not be negligible depending on your needs. You should still normalize the final
	// relevance scores using the appropriate method below.
	
	
	// SearchKit is extremely flexible and quite powerful with regards to query processing and search 
	// options. It supports phrasal, prefix, suffix and boolean searching. Documentation describes the
	// syntax as "Google-like".
	
	// Often, however, it will not be enough to simply pass a user generated string directly to 
	// SearchKit. Cocoa developers accustomed to the simplicity of predicate syntax such as 
	// contains[cd] will wonder why SearchKit doesn't provide this kind of searching directly.
	
	// While diacrtical and case sensitive issues are automatically handled, SearchKit otherwise 
	// looks for exact matches unless you surround your strings with the wildcard character. For 
	// example, predicate syntax such as "contains[cd] tune" must look like "*tune*" to SearchKit. If
	// your user expects this kind of functionality but doesn't know or shouldn't have to correctly 
	// format the string, it will be up to you to make the necessary adjustments.
	
	// See the "How Search Kit Performs Searches" subsection in the SearchKit documentation for more 
	// info on sytnax.
	
- (float*) copyNormalizedRankings:(float*)inRankings;
- (NSArray*) normalizedRankingsArray:(NSArray*)inRankings;

	// Although search kit does support relevance searching, the results are not normalized and may cover
	// an enormous range. This is a convenience method that converts the results to a value between 0 and 1
	// in proportion to the largest rank. The method returns the rankings in the same order it received them.
	// Usually you will call this method after fetchResults has completed.
	
	// You are responsible for the memory created and returned by copyNormalizedRankings. You should release 
	// it using free(). If you use normazliedRankingsArray the memory is already autoreleased.

- (BOOL) isStillSearching;
- (void) cancelSearch;

	// Use these methods to check the status of the index and to cancel any current searches. Normally
	// you won't need to check if a search is continuing, as multiple calls to fetchResults:ranks: will
	// exhaust the search results. But you may want to cancel a search prematurely, if, for example,
	// the user changes the query. It is always safe to call cancelSearch even when no search is currely
	// taking place.

#pragma mark -
#pragma mark Document Terms

	// The following methods may be used to establish a lexicon or glossary. They provide access to
	// the two-way term <-> document associations in the index and can be used to get all the terms
	// in the index, all the terms in a document, all the documents associated with a term, and the
	// number of times a term appears in the index or in a document. Yeah, it's awesome.
	
	// The following methods refer to documentURIs instead of fileURLs, but it does not matter what
	// kind of URL object you are passing to them. Term management does not distinguish between
	// file based or free-standing text content. I have defaulted to URI because it is a more
	// general acronym.

- (NSArray*) allTerms;
	
	// Returns all the terms used in your the search store. You must have specified 
	// kSKIndexInvertedVector when creating the store, as is the case for all of the following 
	// document <-> term methods.

- (NSUInteger) documentCountForTerm:(NSString*)inTerm;

	// Returns the total number of documents associated with a term. This is a relatively fast
	// method and can be used to provide a document count for a given term without actually
	// retrieving the documents.
	
- (NSArray*) documentsForTerm:(NSString*)inTerm;

	// Returns an array of URLs / URIs identifying the documents which contain the specified term.
	// This is the good stuff right here, allowing you to discover relationships between data sets
	// depending on the document content. This kind of capability could form the basis of a much
	// more comprehensive semantic engine.
	
- (NSUInteger) termCountForDocument:(NSURL*)inDocumentURI;

	// Returns the total number of distinct terms associated with a document. This is a relatively
	// fast method and can be used to provide a term count for a document without actually
	// retrieving the document's terms.
	
- (NSArray*) termsForDocument:(NSURL*)inDocumentURI;
	
	// Retrurns an array of NSString objects identifying the terms contained within a document.
	// This is the other good stuff, allowing you to extract a list of unique words contained
	// within a document. You can then call documentsForTerm: to get every other document in the
	// index which contains a term in this array.
	
- (NSUInteger) frequencyOfTerm:(NSString*)inTerm inDocument:(NSURL*)inDocumentURI;

	// Returns the total number of times a specific term occurs in a document.

@end
