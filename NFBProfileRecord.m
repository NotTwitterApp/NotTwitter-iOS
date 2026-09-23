#import "NFBProfileRecord.h"

NSString *NFBProfileString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
NSUInteger NFBProfileCharacterCount(NSString *text) {
  NSUInteger count = 0, index = 0;
  while (index < text.length) { index = NSMaxRange([text rangeOfComposedCharacterSequenceAtIndex:index]); count++; }
  return count;
}
NSString *NFBProfileNormalizedWebsite(NSString *text) {
  NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (value.length && [value rangeOfString:@":"].location == NSNotFound) value = [@"https://" stringByAppendingString:value];
  return value;
}
static NSError *NFBProfileValidationError(NSString *message) {
  return [NSError errorWithDomain:@"NFBProfileEditor" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
NSError *NFBProfilePatchError(NSDictionary *patch) {
  NSDictionary *limits = @{@"displayName":@[@64,@640,@"Name"], @"description":@[@256,@2560,@"Bio"], @"pronouns":@[@20,@200,@"Pronouns"], @"com.nottwitter.location":@[@30,@300,@"Location"]};
  NSSet *allowed = [NSSet setWithArray:@[@"displayName",@"description",@"pronouns",@"website",@"avatar",@"banner",@"com.nottwitter.location",@"com.nottwitter.birthDate"]];
  for (NSString *key in patch) {
    if (![allowed containsObject:key]) return NFBProfileValidationError(@"This profile field cannot be edited here.");
    id value = [patch objectForKey:key];
    if (value == NSNull.null) continue;
    if ([key isEqualToString:@"avatar"] || [key isEqualToString:@"banner"]) {
      if (![value isKindOfClass:NSDictionary.class] || ![[value objectForKey:@"$type"] isEqual:@"blob"] || ![NFBProfileString([[value objectForKey:@"ref"] isKindOfClass:NSDictionary.class] ? [[value objectForKey:@"ref"] objectForKey:@"$link"] : nil) length] || ![@[@"image/jpeg",@"image/png"] containsObject:[value objectForKey:@"mimeType"]] || ![[value objectForKey:@"size"] isKindOfClass:NSNumber.class] || [[value objectForKey:@"size"] integerValue] <= 0 || [[value objectForKey:@"size"] integerValue] > 1000000) return NFBProfileValidationError(@"The server did not return a valid profile image.");
      continue;
    }
    if (![value isKindOfClass:NSString.class]) return NFBProfileValidationError(@"Invalid profile text.");
    NSArray *limit = [limits objectForKey:key];
    if (limit && (NFBProfileCharacterCount(value) > [[limit objectAtIndex:0] unsignedIntegerValue] || [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > [[limit objectAtIndex:1] unsignedIntegerValue]))
      return NFBProfileValidationError([NSString stringWithFormat:@"%@ must fit within %@ characters and %@ UTF-8 bytes.", [limit objectAtIndex:2], [limit objectAtIndex:0], [limit objectAtIndex:1]]);
    if ([key isEqualToString:@"website"] && [value length]) {
      NSURLComponents *url = [NSURLComponents componentsWithString:value];
      if (![@[@"https",@"http"] containsObject:url.scheme.lowercaseString] || !url.host.length || [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound)
        return NFBProfileValidationError(@"Enter a valid website address, such as https://example.com.");
    }
    if ([key isEqualToString:@"com.nottwitter.birthDate"] && [value length]) {
      NSDateFormatter *format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; format.dateFormat = @"yyyy-MM-dd"; format.lenient = NO;
      NSDate *date = [format dateFromString:value];
      if (!date || ![[format stringFromDate:date] isEqual:value] || [date timeIntervalSinceNow] > 0) return NFBProfileValidationError(@"Choose a valid birth date in the past.");
    }
  }
  return nil;
}
NSDictionary *NFBProfileRecordApplyingPatch(NSDictionary *record, NSDictionary *patch) {
  NSMutableDictionary *result = [record mutableCopy] ?: [NSMutableDictionary new];
  [result setObject:@"app.bsky.actor.profile" forKey:@"$type"];
  for (NSString *key in patch) {
    id value = [patch objectForKey:key];
    if (value == NSNull.null || ([value isKindOfClass:NSString.class] && ![value length])) [result removeObjectForKey:key];
    else [result setObject:value forKey:key];
  }
  return result;
}
NSDictionary *NFBProfileViewApplyingRecord(NSDictionary *profile, NSDictionary *record, NSString *endpoint) {
  NSMutableDictionary *result = [profile mutableCopy];
  [result setObject:record forKey:@"profileRecord"];
  for (NSString *key in @[@"displayName",@"description",@"website",@"pronouns"]) {
    NSString *value = NFBProfileString([record objectForKey:key]);
    [result setObject:value forKey:key];
  }
  for (NSString *key in @[@"avatar",@"banner"]) {
    NSDictionary *blob = [record objectForKey:key];
    NSDictionary *ref = [blob isKindOfClass:NSDictionary.class] ? [blob objectForKey:@"ref"] : nil;
    NSString *cid = NFBProfileString([ref isKindOfClass:NSDictionary.class] ? [ref objectForKey:@"$link"] : nil);
    NSString *oldURL = NFBProfileString([result objectForKey:key]);
    if (!cid.length) [result removeObjectForKey:key];
    else if ([oldURL rangeOfString:cid].location == NSNotFound && endpoint.length) {
      NSURLComponents *url = [NSURLComponents componentsWithString:[endpoint stringByAppendingString:@"/xrpc/com.atproto.sync.getBlob"]];
      url.queryItems = @[[NSURLQueryItem queryItemWithName:@"did" value:NFBProfileString([profile objectForKey:@"did"])], [NSURLQueryItem queryItemWithName:@"cid" value:cid]];
      [result setObject:url.URL.absoluteString ?: @"" forKey:key];
    }
    if (![NFBProfileString([result objectForKey:key]) isEqual:oldURL]) [result removeObjectForKey:[@"_nfbLoaded" stringByAppendingString:key.capitalizedString]];
  }
  [result setObject:NFBProfileString([record objectForKey:@"com.nottwitter.location"]) forKey:@"location"];
  NSString *birthday = NFBProfileString([record objectForKey:@"com.nottwitter.birthDate"]);
  if (birthday.length) [result setObject:birthday forKey:@"birthday"];
  else if (![record objectForKey:@"birthday"]) [result removeObjectForKey:@"birthday"];
  return result;
}
