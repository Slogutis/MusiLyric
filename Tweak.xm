#include <stdio.h>
#include <stdlib.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <sys/sysctl.h>
#import <substrate.h>
#import <CommonCrypto/CommonCrypto.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaRemote.h>
extern const char *__progname;

@interface MPAVItem : NSObject
@property(readonly, nonatomic) NSString *mainTitle;
@property(readonly, nonatomic) NSString *lyrics;
@property(readonly, nonatomic) NSString *albumArtist;
@property(readonly, nonatomic) NSString *artist;
@property(readonly, nonatomic) NSString *album;
@property(readonly, nonatomic) NSString *artworkMIMEType;
@property(readonly, nonatomic) NSData *artworkImageData;

@property (nonatomic,retain) id LyricReceived;

- (double)durationInSeconds;
- (void)setupPlaybackInfo;
@end

NSString* encodeBase64WithData(NSData* theData)
{
	@autoreleasepool {
		const uint8_t* input = (const uint8_t*)[theData bytes];
		NSInteger length = [theData length];
		static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
		NSMutableData* data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
		uint8_t* output = (uint8_t*)data.mutableBytes;
		NSInteger i;
		for (i=0; i < length; i += 3) {
			NSInteger value = 0;
			NSInteger j;
			for (j = i; j < (i + 3); j++) {
				value <<= 8;
				if (j < length) {
					value |= (0xFF & input[j]);
				}
			}
			NSInteger theIndex = (i / 3) * 4;
			output[theIndex + 0] =			  table[(value >> 18) & 0x3F];
			output[theIndex + 1] =			  table[(value >> 12) & 0x3F];
			output[theIndex + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
			output[theIndex + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
		}
		return [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
	}
}
NSString* hmacSHA1BinBase64(NSString* data, NSString* key) 
{
	@autoreleasepool {
		const char *cKey  = [key cStringUsingEncoding:NSASCIIStringEncoding];
		const char *cData = [data cStringUsingEncoding:NSASCIIStringEncoding];
		unsigned char cHMAC[CC_SHA1_DIGEST_LENGTH];
		CCHmac(kCCHmacAlgSHA1, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
		NSData *HMAC = [[NSData alloc] initWithBytes:cHMAC length:sizeof(cHMAC)];
		NSString *hash = encodeBase64WithData(HMAC);
		return hash;
	}
}
NSString* urlEncodeUsingEncoding(NSString* encoding)
{
	static __strong NSString* kCodes = @"!*'\"();:@&=+$,/?%#[] ";
	return (NSString*)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)encoding, NULL, (CFStringRef)kCodes, CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
}

NSString* getLyricNow(MPAVItem* item, NSDictionary* metadata)
{
	@try {
			NSString *artist = [NSString string];
			NSString *album = [NSString string];
			NSString *album_artist = [NSString string];
			NSString *track = [NSString string];
			NSString *duration = [NSString string];
			if(item) {
				artist = [item.artist?:artist copy];
				album = [item.album?:album copy];
				album_artist = [item.albumArtist?:album_artist copy];
				track = [item.mainTitle?:track copy];
				duration = [[item durationInSeconds]?[@([item durationInSeconds]) stringValue]:duration copy];
			}
			if(metadata) {
				artist = [[metadata objectForKey:@"artist"]?:artist copy];
				album = [[metadata objectForKey:@"album"]?:album copy];
				album_artist = [[metadata objectForKey:@"albumArtist"]?:album_artist copy];
				track = [[metadata objectForKey:@"mainTitle"]?:track copy];
				duration = [[metadata objectForKey:@"durationInSeconds"]?[[metadata objectForKey:@"durationInSeconds"] stringValue]:duration copy];
			}
			
			static __strong NSString* token = @"160203df69efabfaf0b50f2b7b82aaad0206ce701d1c55895ec22f";
			static __strong NSString* sigFormat = @"&signature=%@&signature_protocol=sha1";
			static __strong NSString* urlFormat = @"https://apic.musixmatch.com/ws/1.1/macro.subtitles.get?app_id=mac-ios-v2.0&usertoken=%@&q_duration=%@&tags=playing&q_album_artist=%@&q_track=%@&q_album=%@&page_size=1&subtitle_format=mxm&f_subtitle_length_max_deviation=1&user_language=pt&f_tracking_url=html&f_subtitle_length=%@&track_fields_set=ios_track_list&q_artist=%@&format=json";
			NSString* prepareString = [NSString stringWithFormat:urlFormat, token, duration, urlEncodeUsingEncoding(album_artist), urlEncodeUsingEncoding(track), urlEncodeUsingEncoding(album), duration, urlEncodeUsingEncoding(artist)];
			NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
			[formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
			[formatter setDateFormat:@"yyyMMdd"];
			NSString* dateToday = [NSString stringWithFormat:@"%d", [[formatter stringFromDate:[NSDate date]] intValue]];
			NSURL* UrlString = [NSURL URLWithString:[prepareString stringByAppendingString:[NSString stringWithFormat:sigFormat, urlEncodeUsingEncoding(hmacSHA1BinBase64([prepareString stringByAppendingString:dateToday], @"secretsuper"))]]];
			NSString* retLyric = nil;
			if(UrlString != nil) {
				NSError *error = nil;
				NSHTTPURLResponse *responseCode = nil;
				NSMutableURLRequest *Request = [[NSMutableURLRequest alloc]	initWithURL:UrlString cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:15.0];
				[Request setHTTPMethod:@"GET"];
				[Request setValue:@"default" forHTTPHeaderField:@"Cookie"];
				[Request setValue:@"default" forHTTPHeaderField:@"x-mxm-endpoint"];
				[Request setValue:@"Musixmatch/6.0.1 (iPhone; iOS 9.2.1; Scale/2.00)" forHTTPHeaderField:@"User-Agent"];
				NSData *receivedData = [NSURLConnection sendSynchronousRequest:Request returningResponse:&responseCode error:&error];
				if(receivedData && !error) {
					NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:receivedData?:[NSData data] options:NSJSONReadingMutableContainers error:nil];
					static __strong NSDictionary* dice = [NSDictionary dictionary];
					retLyric = [[[[[[[[JSON?:dice objectForKey:@"message"]?:dice objectForKey:@"body"]?:dice objectForKey:@"macro_calls"]?:dice objectForKey:@"track.lyrics.get"]?:dice objectForKey:@"message"]?:dice objectForKey:@"body"]?:dice objectForKey:@"lyrics"]?:dice objectForKey:@"lyrics_body"];
				}
			}
			if(retLyric) {
				return retLyric;
			}			
	} @catch (NSException * e) {
	}
	return nil;
}

@interface MLTapGestureRecognizer : UITapGestureRecognizer
@end
@implementation MLTapGestureRecognizer
@end
static BOOL showLiric = NO;
static void toggleLiricView(id target, SEL targetCallBack, UIView* coverTap, BOOL toggled)
{
	if(!coverTap) {
		return;
	}
	if(toggled) {
		coverTap.alpha = coverTap.alpha>0.5?0.3f:1.0f;
		showLiric = coverTap.alpha<0.5?NO:YES;
	}	
	if(UIView* oldRem = [[coverTap superview] viewWithTag:4564]) {
		[oldRem removeFromSuperview];
		coverTap.alpha = 1.0f;
	}
	if(showLiric) {
		return;
	}
	UITextView *liricTextField = [[UITextView alloc] initWithFrame:coverTap.frame];
	MLTapGestureRecognizer *singleFingerTap = [[MLTapGestureRecognizer alloc] initWithTarget:target action:targetCallBack];
	[liricTextField addGestureRecognizer:singleFingerTap];
	liricTextField.backgroundColor = [UIColor clearColor];
	liricTextField.textColor = [UIColor whiteColor];
	liricTextField.editable = NO;
	liricTextField.font = [UIFont fontWithName:@".SFUIText-Regular" size:14];
	liricTextField.textAlignment = NSTextAlignmentCenter;
	liricTextField.text = @"Loading...";
	[liricTextField setScrollEnabled:YES];
	[liricTextField setUserInteractionEnabled:YES];
	liricTextField.tag = 4564;
	[[coverTap superview] addSubview:liricTextField];
	coverTap.alpha = 0.3f;
	if(YES) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			usleep(1000000);
			if(YES) {
				MRMediaRemoteGetNowPlayingInfo(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(CFDictionaryRef result) {
					if(id retLyric = getLyricNow(nil, @{
						@"artist": [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist]?:[NSString string],
						@"albumArtist": [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist]?:[NSString string],
						@"album": [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum]?:[NSString string],
						@"mainTitle": [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle]?:[NSString string],
						@"durationInSeconds": [(__bridge NSDictionary *)result objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoDuration]?:@(0),
					})) {
						dispatch_async(dispatch_get_main_queue(), ^(){
							if(UITextView* liricTextFieldGet = (UITextView*)[[coverTap superview] viewWithTag:4564]) {
								liricTextFieldGet.text = retLyric;
							}
						});
					}
				});
			}
		});
	}
}


%group Music
%hook MPAVItem
%property (nonatomic,retain) id LyricReceived;
- (id)lyrics
{
	id ret = %orig;
	if(!ret) {
		if(self.LyricReceived) {
			ret = self.LyricReceived;
		} else {
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				if(id retLyric = getLyricNow(self, nil)) {
					self.LyricReceived = retLyric;
				}
			});
		}
	}
	return ret;
}
%end
%end

%group Spotify
static UIView* SPcoverArtView = nil;
%hook SPTNowPlayingCoverArtController
- (void)coverArtModelDidChangeLoadingState:(id)arg1
{
	%orig;
	toggleLiricView(self, @selector(coverArtViewTapped:), SPcoverArtView, NO);
}
- (void)coverArtViewTapped:(UITapGestureRecognizer *)gesture
{
	if(gesture && ![gesture isKindOfClass:%c(MLTapGestureRecognizer)]) {
		SPcoverArtView = [gesture view];
	}
	toggleLiricView(self, @selector(coverArtViewTapped:), SPcoverArtView, YES);
	%orig;
}
%end
%end

%group Pandora
static UIView* PAcoverArtView = nil;
@interface PMNowPlayingPhoneTrackCard : NSObject
- (BOOL)isNowPlaying;
- (BOOL)isShowingExpandedTrackDetails;
@end
%hook PMNowPlayingPhoneTrackCard
- (void)updateViewsForIsNowPlayingChange
{
	%orig;
	if(PAcoverArtView) {
		if(UIView* oldRem = [[PAcoverArtView superview] viewWithTag:4564]) {
			[oldRem removeFromSuperview];
			PAcoverArtView.alpha = 1.0f;
		}
	}
}
- (void)toggleTrackDetailsView:(UIButton *)button
{
	%orig;
	if(PAcoverArtView) {
		if(UIView* oldRem = [[PAcoverArtView superview] viewWithTag:4564]) {
			[oldRem removeFromSuperview];
			PAcoverArtView.alpha = 1.0f;
		}
	}
}
- (void)albumCoverPressed:(UIButton *)button
{
	if(![self isNowPlaying] || ![self isShowingExpandedTrackDetails]) {
		%orig;
		return;
	}
	if(button && ![button isKindOfClass:%c(MLTapGestureRecognizer)]) {
		PAcoverArtView = [button superview];
	}
	toggleLiricView(self, @selector(albumCoverPressed:), PAcoverArtView, YES);
}
%end
%end

%ctor
{
	if (strcmp(__progname, "Spotify") == 0) {
		%init(Spotify);
	} else if (strcmp(__progname, "Pandora") == 0) {
		%init(Pandora);
	} else {
		%init(Music);
	}
}

