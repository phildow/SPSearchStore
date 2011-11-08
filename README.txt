
//
//  SPSearchStore.h
//  SPSearchStore
//
//  Created by Philip Dow on 6/6/11.
//  Copyright 2011 Philip Dow /Sprouted. All rights reserved.
//	phil@phildow.net / phil@getsprouted.com
//
//
//	Refer to redistribution and use conditions in class and header files
//	BSD License

Summary
SPSearchStore is an Obj-C wrapper for the SearchKit API. SearchKit offers powerful document indexing and "google-like" querying to CoreFoundation apps. SPSearchStore makes the API accessible to Cocoa applications by way of a simple public interface.

SPSearchStore also provides access to the complete two-way to-many documents / terms graph contained in a SearchKit index, establishing the foundation for more complex analysis based on the semantic relationships among an arbitrary collection of documents.

SPSearchStore is thread safe. You may use multiple threads to read from and write to the search store. SPSearchStore uses locks to manage access to the underlying data.

Workflow
As the included application demonstrates, the workflow consists of three steps: 1. establishing an index and 2. performing searches or 3. performing document / term analysis.

Don't forget to add the CoreServices framework to your project and include it wherever you are using SPSearchStore:

#import <CoreServices/CoreServices.h>


1. Establishing an index

A. Set up default text analysis options prior to store creation:

[SPSearchStore setDefaultTextAnalysisOption:[NSNumber numberWithInteger:2] forKey:(NSString *)kSKMinTermLength];

B. Create a memory or disk based store with a single call:

searchStore = [[SPSearchStore alloc] initStoreWithMemory:nil type:kSKIndexInvertedVector];

C. You can then set store behavior:

searchStore.usesSpotlightImporters = YES;
searchStore.usesConcurrentIndexing = NO;

D. And add content to the store:

[searchStore addDocument:(NSURL*)obj typeHint:nil];


2. Performing a Search

A. Initialize a store search from a query string and query options:

NSString *searchString = @"foo* && *bar";
[searchStore prepareSearch:searchString options:kSKSearchOptionDefault];

B. Fetch the search results either at one time or with multiple calls:

NSArray * results = nil;
NSArray * ranks = nil;
[searchStore fetchResults:&results ranksArray:&ranks untilFinished:YES];

C. Normalize the relevancy results:

NSArray * normalizedRanks = [searchStore normalizedRankingsArray:ranks];


2. Performing Document / Term Analysis

A. Get all the terms or documents in the search index:

NSArray *allDocs = [searchStore allDocuments];
NSArray *terms = [searchStore allTerms];

B. Get all the unique terms contained in a specific document:

NSURL *docURI = ...;
NSArray *docTerms = [searchStore termsForDocument:docURI];

C. Get all the documents which contain a specific term

NSString *term = @"term";
NSArray *docs = [searchStore documentsForTerm:term];


Limitations
SPSearchStore provides access to most of SearchKit's functionality, but there are a couple of noticeable limitations.

1. No support for document hierarchies: SearchKit supports the hierarchical indexing of document content, whether file based on free-standing text. SPSearchStore does not provide an interface to this mechanism.

2. No support for text summarization: SearchKit includes a set of APIs for summarizing documents. SPSearchStore does not support this functionality, choosing instead to focus on query and document/term capabilities. It should, however, be trivial to add a summarization category to NSString.


Concerns
In the past there have been bugs reported with SearchKit's use of 3rd party Spotlight importers. There have also been more recent reports of memory issues with SearchKit. SPSearchStore could benefit from a comprehensive set of UnitTests for different document types and indexing conditions.

Perhaps most annoyingly, SearchKit only indexes the textual content of files. It does not index any other metadata information nor does it index the file's name. Users will probably expect searches to match file names, but this is something you must accomplish separately, probably using NSPredicate.