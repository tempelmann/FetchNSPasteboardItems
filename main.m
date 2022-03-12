//
//  main.m
//  FetchNSPasteboardItems
//
//  Created by Thomas Tempelmann on 12.03.22.
//  Copyright © 2022 Thomas Tempelmann.
//

#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <libgen.h>

static char *pname;

static void usage()
{
	fprintf(stderr, "Usage:\n  %s [-atpj] [-n pbname]\n\n"
	  	"  a: always include items array, even if there's only one.\n"
		"  p: add plist output for each type.\n"
		"  t: add textual output for each type.\n"
		"  j: output JSON format instead of plist XML.\n"
	  	"  n: {general | ruler | find | font} or custom pb name.\n"
	  	"\nWritten 2022 by Thomas Tempelmann, <tempelmann@gmail.com>, apps.tempel.org\n", pname);
	exit(1);
}

static NSString *hexadecimalString (NSData *data)	// from https://stackoverflow.com/a/9084784/43615
{
	const unsigned char *dataBuffer = (const unsigned char *)[data bytes];
	if (!dataBuffer) return nil;
	NSUInteger dataLength  = [data length];
	NSMutableString *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
	for (int i = 0; i < dataLength; ++i) {
		[hexString appendString:[NSString stringWithFormat:@"%02lx", (unsigned long)dataBuffer[i]]];
	}
	return hexString;
}

static NSData *dataWithHexString(NSString *hex)	// from Apple's "NSData+HexString.h"
{
	char buf[3] = {0};
	size_t len = [hex length];
	unsigned char *bytes = malloc(len/2);
	unsigned char *bp = bytes;
	for (CFIndex i = 0; i < len; i += 2) {
		buf[0] = [hex characterAtIndex:i];
		buf[1] = [hex characterAtIndex:i+1];
		char *b2 = NULL;
		*bp++ = strtol(buf, &b2, 16);
	}
	
	return [NSData dataWithBytesNoCopy:bytes length:len/2 freeWhenDone:YES];
}

static void addToDict(NSMutableDictionary *output, NSArray<NSString*>*types, id pb, bool textual, bool plistdata, bool jsonout)
{
	output[@"types"] = types;
	NSMutableDictionary<NSString*,NSString*> *decoded = NSMutableDictionary.new;
	output[@"translatedTypes"] = decoded;
	NSMutableDictionary<NSString*,NSData*> *datas = NSMutableDictionary.new;
	output[@"dataForType"] = datas;
	NSMutableDictionary<NSString*,NSString*> *texts = textual ? NSMutableDictionary.new : nil;
	if (texts) output[@"textForType"] = texts;
	NSMutableDictionary<NSString*,NSString*> *plists = plistdata ? NSMutableDictionary.new : nil;
	if (plists) output[@"plistForType"] = plists;
	for (NSString *uti in types) {
		id data = [pb dataForType:uti];
		if (data) {
			if (jsonout) {
				data = hexadecimalString (data);
			}
			datas[uti] = data;
		}
		if (texts) {
			NSString *text = [pb stringForType:uti];
			if (text) {
				texts[uti] = text;
			}
		}
		if (plists) {
			id pl = [pb propertyListForType:uti];
			if (pl) {
				plists[uti] = pl;
			}
		}
		NSString *type = nil;
		if ([uti hasPrefix:@"CorePasteboardFlavorType 0x"]) {
			NSString *hex = [uti substringWithRange:NSMakeRange(27,8)];
			NSData *d = dataWithHexString(hex);
			type = [NSString stringWithFormat:@"'%@'", [NSString.alloc initWithData:d encoding:NSASCIIStringEncoding]];
		}
		if (!type) {
			NSString *nstype = CFBridgingRelease(UTTypeCopyPreferredTagWithClass ((__bridge CFStringRef _Nonnull)(uti), kUTTagClassNSPboardType));
			if (nstype) {
				type = nstype;
			}
		}
		if (!type && [uti hasPrefix:@"dyn."]) {
			NSString *ostype = CFBridgingRelease(UTTypeCopyPreferredTagWithClass ((__bridge CFStringRef _Nonnull)(uti), kUTTagClassOSType));
			if (ostype) {
				type = [NSString stringWithFormat:@"'%@'", ostype];
			}
		}
		if (type && ![type isEqualToString:uti]) {
			decoded[uti] = type;
		}
	}
}

int main(int argc, const char * argv[])
{
	pname = basename((char*)argv[0]);
	
	@autoreleasepool {
		NSString *pbName = nil;
		bool alwaysWithItems = false;
		bool textual = false;
		bool plistdata = false;
		bool jsonout = false;
		
		char ch;
		while ((ch = getopt(argc, (char **)argv, "?hjatpn:")) != -1) {
			switch (ch) {
			  case 'n':
			  	pbName = [NSString stringWithUTF8String:optarg];
				break;

			  case 'j':
			  	jsonout = true;
			  	break;

			  case 'a':
			  	alwaysWithItems = true;
			  	break;

			  case 't':
			  	textual = true;
			  	break;

			  case 'p':
			  	plistdata = true;
			  	break;

			  case '?':
			  case 'h':
			  default:
				usage();
			}
		}
		argc -= optind;
		argv += optind;
		
		if (jsonout && plistdata) {
			fprintf(stderr, "Can't do the plist option with json output.");
			exit(2);
		}

		NSPasteboard *pb;
		if (pbName == nil || [pbName isEqualToString:@"general"]) {
			pbName = NSGeneralPboard;
		} else if ([pbName isEqualToString:@"drag"]) {
			pbName = NSDragPboard;
		} else if ([pbName isEqualToString:@"find"]) {
			pbName = NSFindPboard;
		} else if ([pbName isEqualToString:@"ruler"]) {
			pbName = NSRulerPboard;
		} else if ([pbName isEqualToString:@"font"]) {
			pbName = NSFontPboard;
		}
		pb = [NSPasteboard pasteboardWithName:pbName];
		if (!pb) {
			fprintf(stderr, "Got no pasteboard");
			exit(3);
		}
		
		NSMutableDictionary *output = NSMutableDictionary.new;
		
		output[@"pbname"] = pbName;

		NSDateFormatter *RFC3339DateFormatter = [[NSDateFormatter alloc] init];
		RFC3339DateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		RFC3339DateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
		output[@"when"] = [RFC3339DateFormatter stringFromDate:NSDate.new];
		
		addToDict (output, pb.types, pb, textual, plistdata, jsonout);
		
		NSArray<NSPasteboardItem*> *pbItems = pb.pasteboardItems;
		if (alwaysWithItems || pbItems.count > 1) {
			NSMutableArray<NSDictionary*> *items = NSMutableArray.new;
			output[@"items"] = items;
			for (NSPasteboardItem *item in pbItems) {
				NSMutableDictionary *itemDict = NSMutableDictionary.new;
				[items addObject:itemDict];
				addToDict (itemDict, item.types, item, textual, plistdata, jsonout);
			}
		}
		
		NSData *out_data = nil;
		if (jsonout) {
			// write to putput in JSON format
			out_data = [NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:nil];
		} else {
			// write to putput in xml plist format
			NSString *errMsg = nil;
			out_data = [NSPropertyListSerialization dataFromPropertyList:output format:NSPropertyListXMLFormat_v1_0 errorDescription:&errMsg];
		}
		NSString *out_str = [NSString.alloc initWithData:out_data encoding:NSUTF8StringEncoding];
		printf("%s", out_str.UTF8String);
	}
	return 0;
}
