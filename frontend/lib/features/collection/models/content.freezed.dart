// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'content.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ShareCard {

 int get id; String get platform; String get url; String? get title; String? get summary; String? get description;@JsonKey(name: 'author_name') String? get authorName;@JsonKey(name: 'author_id') String? get authorId;@JsonKey(name: 'author_avatar_url') String? get authorAvatarUrl;@JsonKey(name: 'content_type') String? get contentType;@JsonKey(name: 'cover_url') String? get coverUrl;@JsonKey(name: 'cover_color') String? get coverColor;@JsonKey(name: 'media_urls') List<String> get mediaUrls; List<String> get tags;@JsonKey(name: 'view_count') int get viewCount;@JsonKey(name: 'like_count') int get likeCount;@JsonKey(name: 'collect_count') int get collectCount;@JsonKey(name: 'share_count') int get shareCount;@JsonKey(name: 'comment_count') int get commentCount;@JsonKey(name: 'published_at') DateTime? get publishedAt;@JsonKey(name: 'raw_metadata') Map<String, dynamic>? get rawMetadata;
/// Create a copy of ShareCard
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareCardCopyWith<ShareCard> get copyWith => _$ShareCardCopyWithImpl<ShareCard>(this as ShareCard, _$identity);

  /// Serializes this ShareCard to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareCard&&(identical(other.id, id) || other.id == id)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.url, url) || other.url == url)&&(identical(other.title, title) || other.title == title)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.description, description) || other.description == description)&&(identical(other.authorName, authorName) || other.authorName == authorName)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.authorAvatarUrl, authorAvatarUrl) || other.authorAvatarUrl == authorAvatarUrl)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.coverColor, coverColor) || other.coverColor == coverColor)&&const DeepCollectionEquality().equals(other.mediaUrls, mediaUrls)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.viewCount, viewCount) || other.viewCount == viewCount)&&(identical(other.likeCount, likeCount) || other.likeCount == likeCount)&&(identical(other.collectCount, collectCount) || other.collectCount == collectCount)&&(identical(other.shareCount, shareCount) || other.shareCount == shareCount)&&(identical(other.commentCount, commentCount) || other.commentCount == commentCount)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&const DeepCollectionEquality().equals(other.rawMetadata, rawMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,platform,url,title,summary,description,authorName,authorId,authorAvatarUrl,contentType,coverUrl,coverColor,const DeepCollectionEquality().hash(mediaUrls),const DeepCollectionEquality().hash(tags),viewCount,likeCount,collectCount,shareCount,commentCount,publishedAt,const DeepCollectionEquality().hash(rawMetadata)]);

@override
String toString() {
  return 'ShareCard(id: $id, platform: $platform, url: $url, title: $title, summary: $summary, description: $description, authorName: $authorName, authorId: $authorId, authorAvatarUrl: $authorAvatarUrl, contentType: $contentType, coverUrl: $coverUrl, coverColor: $coverColor, mediaUrls: $mediaUrls, tags: $tags, viewCount: $viewCount, likeCount: $likeCount, collectCount: $collectCount, shareCount: $shareCount, commentCount: $commentCount, publishedAt: $publishedAt, rawMetadata: $rawMetadata)';
}


}

/// @nodoc
abstract mixin class $ShareCardCopyWith<$Res>  {
  factory $ShareCardCopyWith(ShareCard value, $Res Function(ShareCard) _then) = _$ShareCardCopyWithImpl;
@useResult
$Res call({
 int id, String platform, String url, String? title, String? summary, String? description,@JsonKey(name: 'author_name') String? authorName,@JsonKey(name: 'author_id') String? authorId,@JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,@JsonKey(name: 'content_type') String? contentType,@JsonKey(name: 'cover_url') String? coverUrl,@JsonKey(name: 'cover_color') String? coverColor,@JsonKey(name: 'media_urls') List<String> mediaUrls, List<String> tags,@JsonKey(name: 'view_count') int viewCount,@JsonKey(name: 'like_count') int likeCount,@JsonKey(name: 'collect_count') int collectCount,@JsonKey(name: 'share_count') int shareCount,@JsonKey(name: 'comment_count') int commentCount,@JsonKey(name: 'published_at') DateTime? publishedAt,@JsonKey(name: 'raw_metadata') Map<String, dynamic>? rawMetadata
});




}
/// @nodoc
class _$ShareCardCopyWithImpl<$Res>
    implements $ShareCardCopyWith<$Res> {
  _$ShareCardCopyWithImpl(this._self, this._then);

  final ShareCard _self;
  final $Res Function(ShareCard) _then;

/// Create a copy of ShareCard
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? platform = null,Object? url = null,Object? title = freezed,Object? summary = freezed,Object? description = freezed,Object? authorName = freezed,Object? authorId = freezed,Object? authorAvatarUrl = freezed,Object? contentType = freezed,Object? coverUrl = freezed,Object? coverColor = freezed,Object? mediaUrls = null,Object? tags = null,Object? viewCount = null,Object? likeCount = null,Object? collectCount = null,Object? shareCount = null,Object? commentCount = null,Object? publishedAt = freezed,Object? rawMetadata = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,authorName: freezed == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,authorAvatarUrl: freezed == authorAvatarUrl ? _self.authorAvatarUrl : authorAvatarUrl // ignore: cast_nullable_to_non_nullable
as String?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,coverColor: freezed == coverColor ? _self.coverColor : coverColor // ignore: cast_nullable_to_non_nullable
as String?,mediaUrls: null == mediaUrls ? _self.mediaUrls : mediaUrls // ignore: cast_nullable_to_non_nullable
as List<String>,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,viewCount: null == viewCount ? _self.viewCount : viewCount // ignore: cast_nullable_to_non_nullable
as int,likeCount: null == likeCount ? _self.likeCount : likeCount // ignore: cast_nullable_to_non_nullable
as int,collectCount: null == collectCount ? _self.collectCount : collectCount // ignore: cast_nullable_to_non_nullable
as int,shareCount: null == shareCount ? _self.shareCount : shareCount // ignore: cast_nullable_to_non_nullable
as int,commentCount: null == commentCount ? _self.commentCount : commentCount // ignore: cast_nullable_to_non_nullable
as int,publishedAt: freezed == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,rawMetadata: freezed == rawMetadata ? _self.rawMetadata : rawMetadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShareCard].
extension ShareCardPatterns on ShareCard {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShareCard value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShareCard() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShareCard value)  $default,){
final _that = this;
switch (_that) {
case _ShareCard():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShareCard value)?  $default,){
final _that = this;
switch (_that) {
case _ShareCard() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String platform,  String url,  String? title,  String? summary,  String? description, @JsonKey(name: 'author_name')  String? authorName, @JsonKey(name: 'author_id')  String? authorId, @JsonKey(name: 'author_avatar_url')  String? authorAvatarUrl, @JsonKey(name: 'content_type')  String? contentType, @JsonKey(name: 'cover_url')  String? coverUrl, @JsonKey(name: 'cover_color')  String? coverColor, @JsonKey(name: 'media_urls')  List<String> mediaUrls,  List<String> tags, @JsonKey(name: 'view_count')  int viewCount, @JsonKey(name: 'like_count')  int likeCount, @JsonKey(name: 'collect_count')  int collectCount, @JsonKey(name: 'share_count')  int shareCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(name: 'published_at')  DateTime? publishedAt, @JsonKey(name: 'raw_metadata')  Map<String, dynamic>? rawMetadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShareCard() when $default != null:
return $default(_that.id,_that.platform,_that.url,_that.title,_that.summary,_that.description,_that.authorName,_that.authorId,_that.authorAvatarUrl,_that.contentType,_that.coverUrl,_that.coverColor,_that.mediaUrls,_that.tags,_that.viewCount,_that.likeCount,_that.collectCount,_that.shareCount,_that.commentCount,_that.publishedAt,_that.rawMetadata);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String platform,  String url,  String? title,  String? summary,  String? description, @JsonKey(name: 'author_name')  String? authorName, @JsonKey(name: 'author_id')  String? authorId, @JsonKey(name: 'author_avatar_url')  String? authorAvatarUrl, @JsonKey(name: 'content_type')  String? contentType, @JsonKey(name: 'cover_url')  String? coverUrl, @JsonKey(name: 'cover_color')  String? coverColor, @JsonKey(name: 'media_urls')  List<String> mediaUrls,  List<String> tags, @JsonKey(name: 'view_count')  int viewCount, @JsonKey(name: 'like_count')  int likeCount, @JsonKey(name: 'collect_count')  int collectCount, @JsonKey(name: 'share_count')  int shareCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(name: 'published_at')  DateTime? publishedAt, @JsonKey(name: 'raw_metadata')  Map<String, dynamic>? rawMetadata)  $default,) {final _that = this;
switch (_that) {
case _ShareCard():
return $default(_that.id,_that.platform,_that.url,_that.title,_that.summary,_that.description,_that.authorName,_that.authorId,_that.authorAvatarUrl,_that.contentType,_that.coverUrl,_that.coverColor,_that.mediaUrls,_that.tags,_that.viewCount,_that.likeCount,_that.collectCount,_that.shareCount,_that.commentCount,_that.publishedAt,_that.rawMetadata);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String platform,  String url,  String? title,  String? summary,  String? description, @JsonKey(name: 'author_name')  String? authorName, @JsonKey(name: 'author_id')  String? authorId, @JsonKey(name: 'author_avatar_url')  String? authorAvatarUrl, @JsonKey(name: 'content_type')  String? contentType, @JsonKey(name: 'cover_url')  String? coverUrl, @JsonKey(name: 'cover_color')  String? coverColor, @JsonKey(name: 'media_urls')  List<String> mediaUrls,  List<String> tags, @JsonKey(name: 'view_count')  int viewCount, @JsonKey(name: 'like_count')  int likeCount, @JsonKey(name: 'collect_count')  int collectCount, @JsonKey(name: 'share_count')  int shareCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(name: 'published_at')  DateTime? publishedAt, @JsonKey(name: 'raw_metadata')  Map<String, dynamic>? rawMetadata)?  $default,) {final _that = this;
switch (_that) {
case _ShareCard() when $default != null:
return $default(_that.id,_that.platform,_that.url,_that.title,_that.summary,_that.description,_that.authorName,_that.authorId,_that.authorAvatarUrl,_that.contentType,_that.coverUrl,_that.coverColor,_that.mediaUrls,_that.tags,_that.viewCount,_that.likeCount,_that.collectCount,_that.shareCount,_that.commentCount,_that.publishedAt,_that.rawMetadata);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShareCard extends ShareCard {
  const _ShareCard({required this.id, required this.platform, required this.url, this.title, this.summary, this.description, @JsonKey(name: 'author_name') this.authorName, @JsonKey(name: 'author_id') this.authorId, @JsonKey(name: 'author_avatar_url') this.authorAvatarUrl, @JsonKey(name: 'content_type') this.contentType, @JsonKey(name: 'cover_url') this.coverUrl, @JsonKey(name: 'cover_color') this.coverColor, @JsonKey(name: 'media_urls') final  List<String> mediaUrls = const [], final  List<String> tags = const [], @JsonKey(name: 'view_count') this.viewCount = 0, @JsonKey(name: 'like_count') this.likeCount = 0, @JsonKey(name: 'collect_count') this.collectCount = 0, @JsonKey(name: 'share_count') this.shareCount = 0, @JsonKey(name: 'comment_count') this.commentCount = 0, @JsonKey(name: 'published_at') this.publishedAt, @JsonKey(name: 'raw_metadata') final  Map<String, dynamic>? rawMetadata}): _mediaUrls = mediaUrls,_tags = tags,_rawMetadata = rawMetadata,super._();
  factory _ShareCard.fromJson(Map<String, dynamic> json) => _$ShareCardFromJson(json);

@override final  int id;
@override final  String platform;
@override final  String url;
@override final  String? title;
@override final  String? summary;
@override final  String? description;
@override@JsonKey(name: 'author_name') final  String? authorName;
@override@JsonKey(name: 'author_id') final  String? authorId;
@override@JsonKey(name: 'author_avatar_url') final  String? authorAvatarUrl;
@override@JsonKey(name: 'content_type') final  String? contentType;
@override@JsonKey(name: 'cover_url') final  String? coverUrl;
@override@JsonKey(name: 'cover_color') final  String? coverColor;
 final  List<String> _mediaUrls;
@override@JsonKey(name: 'media_urls') List<String> get mediaUrls {
  if (_mediaUrls is EqualUnmodifiableListView) return _mediaUrls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mediaUrls);
}

 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey(name: 'view_count') final  int viewCount;
@override@JsonKey(name: 'like_count') final  int likeCount;
@override@JsonKey(name: 'collect_count') final  int collectCount;
@override@JsonKey(name: 'share_count') final  int shareCount;
@override@JsonKey(name: 'comment_count') final  int commentCount;
@override@JsonKey(name: 'published_at') final  DateTime? publishedAt;
 final  Map<String, dynamic>? _rawMetadata;
@override@JsonKey(name: 'raw_metadata') Map<String, dynamic>? get rawMetadata {
  final value = _rawMetadata;
  if (value == null) return null;
  if (_rawMetadata is EqualUnmodifiableMapView) return _rawMetadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ShareCard
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShareCardCopyWith<_ShareCard> get copyWith => __$ShareCardCopyWithImpl<_ShareCard>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShareCardToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShareCard&&(identical(other.id, id) || other.id == id)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.url, url) || other.url == url)&&(identical(other.title, title) || other.title == title)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.description, description) || other.description == description)&&(identical(other.authorName, authorName) || other.authorName == authorName)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.authorAvatarUrl, authorAvatarUrl) || other.authorAvatarUrl == authorAvatarUrl)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.coverColor, coverColor) || other.coverColor == coverColor)&&const DeepCollectionEquality().equals(other._mediaUrls, _mediaUrls)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.viewCount, viewCount) || other.viewCount == viewCount)&&(identical(other.likeCount, likeCount) || other.likeCount == likeCount)&&(identical(other.collectCount, collectCount) || other.collectCount == collectCount)&&(identical(other.shareCount, shareCount) || other.shareCount == shareCount)&&(identical(other.commentCount, commentCount) || other.commentCount == commentCount)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&const DeepCollectionEquality().equals(other._rawMetadata, _rawMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,platform,url,title,summary,description,authorName,authorId,authorAvatarUrl,contentType,coverUrl,coverColor,const DeepCollectionEquality().hash(_mediaUrls),const DeepCollectionEquality().hash(_tags),viewCount,likeCount,collectCount,shareCount,commentCount,publishedAt,const DeepCollectionEquality().hash(_rawMetadata)]);

@override
String toString() {
  return 'ShareCard(id: $id, platform: $platform, url: $url, title: $title, summary: $summary, description: $description, authorName: $authorName, authorId: $authorId, authorAvatarUrl: $authorAvatarUrl, contentType: $contentType, coverUrl: $coverUrl, coverColor: $coverColor, mediaUrls: $mediaUrls, tags: $tags, viewCount: $viewCount, likeCount: $likeCount, collectCount: $collectCount, shareCount: $shareCount, commentCount: $commentCount, publishedAt: $publishedAt, rawMetadata: $rawMetadata)';
}


}

/// @nodoc
abstract mixin class _$ShareCardCopyWith<$Res> implements $ShareCardCopyWith<$Res> {
  factory _$ShareCardCopyWith(_ShareCard value, $Res Function(_ShareCard) _then) = __$ShareCardCopyWithImpl;
@override @useResult
$Res call({
 int id, String platform, String url, String? title, String? summary, String? description,@JsonKey(name: 'author_name') String? authorName,@JsonKey(name: 'author_id') String? authorId,@JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,@JsonKey(name: 'content_type') String? contentType,@JsonKey(name: 'cover_url') String? coverUrl,@JsonKey(name: 'cover_color') String? coverColor,@JsonKey(name: 'media_urls') List<String> mediaUrls, List<String> tags,@JsonKey(name: 'view_count') int viewCount,@JsonKey(name: 'like_count') int likeCount,@JsonKey(name: 'collect_count') int collectCount,@JsonKey(name: 'share_count') int shareCount,@JsonKey(name: 'comment_count') int commentCount,@JsonKey(name: 'published_at') DateTime? publishedAt,@JsonKey(name: 'raw_metadata') Map<String, dynamic>? rawMetadata
});




}
/// @nodoc
class __$ShareCardCopyWithImpl<$Res>
    implements _$ShareCardCopyWith<$Res> {
  __$ShareCardCopyWithImpl(this._self, this._then);

  final _ShareCard _self;
  final $Res Function(_ShareCard) _then;

/// Create a copy of ShareCard
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? platform = null,Object? url = null,Object? title = freezed,Object? summary = freezed,Object? description = freezed,Object? authorName = freezed,Object? authorId = freezed,Object? authorAvatarUrl = freezed,Object? contentType = freezed,Object? coverUrl = freezed,Object? coverColor = freezed,Object? mediaUrls = null,Object? tags = null,Object? viewCount = null,Object? likeCount = null,Object? collectCount = null,Object? shareCount = null,Object? commentCount = null,Object? publishedAt = freezed,Object? rawMetadata = freezed,}) {
  return _then(_ShareCard(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,authorName: freezed == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,authorAvatarUrl: freezed == authorAvatarUrl ? _self.authorAvatarUrl : authorAvatarUrl // ignore: cast_nullable_to_non_nullable
as String?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,coverColor: freezed == coverColor ? _self.coverColor : coverColor // ignore: cast_nullable_to_non_nullable
as String?,mediaUrls: null == mediaUrls ? _self._mediaUrls : mediaUrls // ignore: cast_nullable_to_non_nullable
as List<String>,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,viewCount: null == viewCount ? _self.viewCount : viewCount // ignore: cast_nullable_to_non_nullable
as int,likeCount: null == likeCount ? _self.likeCount : likeCount // ignore: cast_nullable_to_non_nullable
as int,collectCount: null == collectCount ? _self.collectCount : collectCount // ignore: cast_nullable_to_non_nullable
as int,shareCount: null == shareCount ? _self.shareCount : shareCount // ignore: cast_nullable_to_non_nullable
as int,commentCount: null == commentCount ? _self.commentCount : commentCount // ignore: cast_nullable_to_non_nullable
as int,publishedAt: freezed == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,rawMetadata: freezed == rawMetadata ? _self._rawMetadata : rawMetadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}


/// @nodoc
mixin _$ContentDetail {

 int get id; String get platform;@JsonKey(name: 'platform_id') String? get platformId;@JsonKey(name: 'content_type') String? get contentType; String get url;@JsonKey(name: 'clean_url') String? get cleanUrl; String get status;@JsonKey(name: 'review_status') String? get reviewStatus; List<String> get tags;@JsonKey(name: 'is_nsfw') bool get isNsfw; String? get title; String? get description;@JsonKey(name: 'author_name') String? get authorName;@JsonKey(name: 'author_id') String? get authorId;@JsonKey(name: 'author_avatar_url') String? get authorAvatarUrl;@JsonKey(name: 'cover_url') String? get coverUrl;@JsonKey(name: 'cover_color') String? get coverColor;@JsonKey(name: 'created_at') DateTime get createdAt;@JsonKey(name: 'updated_at') DateTime get updatedAt;@JsonKey(name: 'published_at') DateTime? get publishedAt;@JsonKey(name: 'media_urls') List<String> get mediaUrls;@JsonKey(name: 'view_count') int get viewCount;@JsonKey(name: 'like_count') int get likeCount;@JsonKey(name: 'collect_count') int get collectCount;@JsonKey(name: 'share_count') int get shareCount;@JsonKey(name: 'comment_count') int get commentCount;@JsonKey(name: 'extra_stats') Map<String, dynamic> get extraStats;@JsonKey(name: 'raw_metadata') Map<String, dynamic>? get rawMetadata;
/// Create a copy of ContentDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContentDetailCopyWith<ContentDetail> get copyWith => _$ContentDetailCopyWithImpl<ContentDetail>(this as ContentDetail, _$identity);

  /// Serializes this ContentDetail to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContentDetail&&(identical(other.id, id) || other.id == id)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.platformId, platformId) || other.platformId == platformId)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.url, url) || other.url == url)&&(identical(other.cleanUrl, cleanUrl) || other.cleanUrl == cleanUrl)&&(identical(other.status, status) || other.status == status)&&(identical(other.reviewStatus, reviewStatus) || other.reviewStatus == reviewStatus)&&const DeepCollectionEquality().equals(other.tags, tags)&&(identical(other.isNsfw, isNsfw) || other.isNsfw == isNsfw)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.authorName, authorName) || other.authorName == authorName)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.authorAvatarUrl, authorAvatarUrl) || other.authorAvatarUrl == authorAvatarUrl)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.coverColor, coverColor) || other.coverColor == coverColor)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&const DeepCollectionEquality().equals(other.mediaUrls, mediaUrls)&&(identical(other.viewCount, viewCount) || other.viewCount == viewCount)&&(identical(other.likeCount, likeCount) || other.likeCount == likeCount)&&(identical(other.collectCount, collectCount) || other.collectCount == collectCount)&&(identical(other.shareCount, shareCount) || other.shareCount == shareCount)&&(identical(other.commentCount, commentCount) || other.commentCount == commentCount)&&const DeepCollectionEquality().equals(other.extraStats, extraStats)&&const DeepCollectionEquality().equals(other.rawMetadata, rawMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,platform,platformId,contentType,url,cleanUrl,status,reviewStatus,const DeepCollectionEquality().hash(tags),isNsfw,title,description,authorName,authorId,authorAvatarUrl,coverUrl,coverColor,createdAt,updatedAt,publishedAt,const DeepCollectionEquality().hash(mediaUrls),viewCount,likeCount,collectCount,shareCount,commentCount,const DeepCollectionEquality().hash(extraStats),const DeepCollectionEquality().hash(rawMetadata)]);

@override
String toString() {
  return 'ContentDetail(id: $id, platform: $platform, platformId: $platformId, contentType: $contentType, url: $url, cleanUrl: $cleanUrl, status: $status, reviewStatus: $reviewStatus, tags: $tags, isNsfw: $isNsfw, title: $title, description: $description, authorName: $authorName, authorId: $authorId, authorAvatarUrl: $authorAvatarUrl, coverUrl: $coverUrl, coverColor: $coverColor, createdAt: $createdAt, updatedAt: $updatedAt, publishedAt: $publishedAt, mediaUrls: $mediaUrls, viewCount: $viewCount, likeCount: $likeCount, collectCount: $collectCount, shareCount: $shareCount, commentCount: $commentCount, extraStats: $extraStats, rawMetadata: $rawMetadata)';
}


}

/// @nodoc
abstract mixin class $ContentDetailCopyWith<$Res>  {
  factory $ContentDetailCopyWith(ContentDetail value, $Res Function(ContentDetail) _then) = _$ContentDetailCopyWithImpl;
@useResult
$Res call({
 int id, String platform,@JsonKey(name: 'platform_id') String? platformId,@JsonKey(name: 'content_type') String? contentType, String url,@JsonKey(name: 'clean_url') String? cleanUrl, String status,@JsonKey(name: 'review_status') String? reviewStatus, List<String> tags,@JsonKey(name: 'is_nsfw') bool isNsfw, String? title, String? description,@JsonKey(name: 'author_name') String? authorName,@JsonKey(name: 'author_id') String? authorId,@JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,@JsonKey(name: 'cover_url') String? coverUrl,@JsonKey(name: 'cover_color') String? coverColor,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'updated_at') DateTime updatedAt,@JsonKey(name: 'published_at') DateTime? publishedAt,@JsonKey(name: 'media_urls') List<String> mediaUrls,@JsonKey(name: 'view_count') int viewCount,@JsonKey(name: 'like_count') int likeCount,@JsonKey(name: 'collect_count') int collectCount,@JsonKey(name: 'share_count') int shareCount,@JsonKey(name: 'comment_count') int commentCount,@JsonKey(name: 'extra_stats') Map<String, dynamic> extraStats,@JsonKey(name: 'raw_metadata') Map<String, dynamic>? rawMetadata
});




}
/// @nodoc
class _$ContentDetailCopyWithImpl<$Res>
    implements $ContentDetailCopyWith<$Res> {
  _$ContentDetailCopyWithImpl(this._self, this._then);

  final ContentDetail _self;
  final $Res Function(ContentDetail) _then;

/// Create a copy of ContentDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? platform = null,Object? platformId = freezed,Object? contentType = freezed,Object? url = null,Object? cleanUrl = freezed,Object? status = null,Object? reviewStatus = freezed,Object? tags = null,Object? isNsfw = null,Object? title = freezed,Object? description = freezed,Object? authorName = freezed,Object? authorId = freezed,Object? authorAvatarUrl = freezed,Object? coverUrl = freezed,Object? coverColor = freezed,Object? createdAt = null,Object? updatedAt = null,Object? publishedAt = freezed,Object? mediaUrls = null,Object? viewCount = null,Object? likeCount = null,Object? collectCount = null,Object? shareCount = null,Object? commentCount = null,Object? extraStats = null,Object? rawMetadata = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,platformId: freezed == platformId ? _self.platformId : platformId // ignore: cast_nullable_to_non_nullable
as String?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,cleanUrl: freezed == cleanUrl ? _self.cleanUrl : cleanUrl // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,reviewStatus: freezed == reviewStatus ? _self.reviewStatus : reviewStatus // ignore: cast_nullable_to_non_nullable
as String?,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,isNsfw: null == isNsfw ? _self.isNsfw : isNsfw // ignore: cast_nullable_to_non_nullable
as bool,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,authorName: freezed == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,authorAvatarUrl: freezed == authorAvatarUrl ? _self.authorAvatarUrl : authorAvatarUrl // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,coverColor: freezed == coverColor ? _self.coverColor : coverColor // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,publishedAt: freezed == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,mediaUrls: null == mediaUrls ? _self.mediaUrls : mediaUrls // ignore: cast_nullable_to_non_nullable
as List<String>,viewCount: null == viewCount ? _self.viewCount : viewCount // ignore: cast_nullable_to_non_nullable
as int,likeCount: null == likeCount ? _self.likeCount : likeCount // ignore: cast_nullable_to_non_nullable
as int,collectCount: null == collectCount ? _self.collectCount : collectCount // ignore: cast_nullable_to_non_nullable
as int,shareCount: null == shareCount ? _self.shareCount : shareCount // ignore: cast_nullable_to_non_nullable
as int,commentCount: null == commentCount ? _self.commentCount : commentCount // ignore: cast_nullable_to_non_nullable
as int,extraStats: null == extraStats ? _self.extraStats : extraStats // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,rawMetadata: freezed == rawMetadata ? _self.rawMetadata : rawMetadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [ContentDetail].
extension ContentDetailPatterns on ContentDetail {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContentDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContentDetail() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContentDetail value)  $default,){
final _that = this;
switch (_that) {
case _ContentDetail():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContentDetail value)?  $default,){
final _that = this;
switch (_that) {
case _ContentDetail() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String platform, @JsonKey(name: 'platform_id')  String? platformId, @JsonKey(name: 'content_type')  String? contentType,  String url, @JsonKey(name: 'clean_url')  String? cleanUrl,  String status, @JsonKey(name: 'review_status')  String? reviewStatus,  List<String> tags, @JsonKey(name: 'is_nsfw')  bool isNsfw,  String? title,  String? description, @JsonKey(name: 'author_name')  String? authorName, @JsonKey(name: 'author_id')  String? authorId, @JsonKey(name: 'author_avatar_url')  String? authorAvatarUrl, @JsonKey(name: 'cover_url')  String? coverUrl, @JsonKey(name: 'cover_color')  String? coverColor, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt, @JsonKey(name: 'published_at')  DateTime? publishedAt, @JsonKey(name: 'media_urls')  List<String> mediaUrls, @JsonKey(name: 'view_count')  int viewCount, @JsonKey(name: 'like_count')  int likeCount, @JsonKey(name: 'collect_count')  int collectCount, @JsonKey(name: 'share_count')  int shareCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(name: 'extra_stats')  Map<String, dynamic> extraStats, @JsonKey(name: 'raw_metadata')  Map<String, dynamic>? rawMetadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContentDetail() when $default != null:
return $default(_that.id,_that.platform,_that.platformId,_that.contentType,_that.url,_that.cleanUrl,_that.status,_that.reviewStatus,_that.tags,_that.isNsfw,_that.title,_that.description,_that.authorName,_that.authorId,_that.authorAvatarUrl,_that.coverUrl,_that.coverColor,_that.createdAt,_that.updatedAt,_that.publishedAt,_that.mediaUrls,_that.viewCount,_that.likeCount,_that.collectCount,_that.shareCount,_that.commentCount,_that.extraStats,_that.rawMetadata);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String platform, @JsonKey(name: 'platform_id')  String? platformId, @JsonKey(name: 'content_type')  String? contentType,  String url, @JsonKey(name: 'clean_url')  String? cleanUrl,  String status, @JsonKey(name: 'review_status')  String? reviewStatus,  List<String> tags, @JsonKey(name: 'is_nsfw')  bool isNsfw,  String? title,  String? description, @JsonKey(name: 'author_name')  String? authorName, @JsonKey(name: 'author_id')  String? authorId, @JsonKey(name: 'author_avatar_url')  String? authorAvatarUrl, @JsonKey(name: 'cover_url')  String? coverUrl, @JsonKey(name: 'cover_color')  String? coverColor, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt, @JsonKey(name: 'published_at')  DateTime? publishedAt, @JsonKey(name: 'media_urls')  List<String> mediaUrls, @JsonKey(name: 'view_count')  int viewCount, @JsonKey(name: 'like_count')  int likeCount, @JsonKey(name: 'collect_count')  int collectCount, @JsonKey(name: 'share_count')  int shareCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(name: 'extra_stats')  Map<String, dynamic> extraStats, @JsonKey(name: 'raw_metadata')  Map<String, dynamic>? rawMetadata)  $default,) {final _that = this;
switch (_that) {
case _ContentDetail():
return $default(_that.id,_that.platform,_that.platformId,_that.contentType,_that.url,_that.cleanUrl,_that.status,_that.reviewStatus,_that.tags,_that.isNsfw,_that.title,_that.description,_that.authorName,_that.authorId,_that.authorAvatarUrl,_that.coverUrl,_that.coverColor,_that.createdAt,_that.updatedAt,_that.publishedAt,_that.mediaUrls,_that.viewCount,_that.likeCount,_that.collectCount,_that.shareCount,_that.commentCount,_that.extraStats,_that.rawMetadata);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String platform, @JsonKey(name: 'platform_id')  String? platformId, @JsonKey(name: 'content_type')  String? contentType,  String url, @JsonKey(name: 'clean_url')  String? cleanUrl,  String status, @JsonKey(name: 'review_status')  String? reviewStatus,  List<String> tags, @JsonKey(name: 'is_nsfw')  bool isNsfw,  String? title,  String? description, @JsonKey(name: 'author_name')  String? authorName, @JsonKey(name: 'author_id')  String? authorId, @JsonKey(name: 'author_avatar_url')  String? authorAvatarUrl, @JsonKey(name: 'cover_url')  String? coverUrl, @JsonKey(name: 'cover_color')  String? coverColor, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt, @JsonKey(name: 'published_at')  DateTime? publishedAt, @JsonKey(name: 'media_urls')  List<String> mediaUrls, @JsonKey(name: 'view_count')  int viewCount, @JsonKey(name: 'like_count')  int likeCount, @JsonKey(name: 'collect_count')  int collectCount, @JsonKey(name: 'share_count')  int shareCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(name: 'extra_stats')  Map<String, dynamic> extraStats, @JsonKey(name: 'raw_metadata')  Map<String, dynamic>? rawMetadata)?  $default,) {final _that = this;
switch (_that) {
case _ContentDetail() when $default != null:
return $default(_that.id,_that.platform,_that.platformId,_that.contentType,_that.url,_that.cleanUrl,_that.status,_that.reviewStatus,_that.tags,_that.isNsfw,_that.title,_that.description,_that.authorName,_that.authorId,_that.authorAvatarUrl,_that.coverUrl,_that.coverColor,_that.createdAt,_that.updatedAt,_that.publishedAt,_that.mediaUrls,_that.viewCount,_that.likeCount,_that.collectCount,_that.shareCount,_that.commentCount,_that.extraStats,_that.rawMetadata);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ContentDetail extends ContentDetail {
  const _ContentDetail({required this.id, required this.platform, @JsonKey(name: 'platform_id') this.platformId, @JsonKey(name: 'content_type') this.contentType, required this.url, @JsonKey(name: 'clean_url') this.cleanUrl, required this.status, @JsonKey(name: 'review_status') this.reviewStatus, required final  List<String> tags, @JsonKey(name: 'is_nsfw') required this.isNsfw, this.title, this.description, @JsonKey(name: 'author_name') this.authorName, @JsonKey(name: 'author_id') this.authorId, @JsonKey(name: 'author_avatar_url') this.authorAvatarUrl, @JsonKey(name: 'cover_url') this.coverUrl, @JsonKey(name: 'cover_color') this.coverColor, @JsonKey(name: 'created_at') required this.createdAt, @JsonKey(name: 'updated_at') required this.updatedAt, @JsonKey(name: 'published_at') this.publishedAt, @JsonKey(name: 'media_urls') final  List<String> mediaUrls = const [], @JsonKey(name: 'view_count') this.viewCount = 0, @JsonKey(name: 'like_count') this.likeCount = 0, @JsonKey(name: 'collect_count') this.collectCount = 0, @JsonKey(name: 'share_count') this.shareCount = 0, @JsonKey(name: 'comment_count') this.commentCount = 0, @JsonKey(name: 'extra_stats') final  Map<String, dynamic> extraStats = const {}, @JsonKey(name: 'raw_metadata') final  Map<String, dynamic>? rawMetadata}): _tags = tags,_mediaUrls = mediaUrls,_extraStats = extraStats,_rawMetadata = rawMetadata,super._();
  factory _ContentDetail.fromJson(Map<String, dynamic> json) => _$ContentDetailFromJson(json);

@override final  int id;
@override final  String platform;
@override@JsonKey(name: 'platform_id') final  String? platformId;
@override@JsonKey(name: 'content_type') final  String? contentType;
@override final  String url;
@override@JsonKey(name: 'clean_url') final  String? cleanUrl;
@override final  String status;
@override@JsonKey(name: 'review_status') final  String? reviewStatus;
 final  List<String> _tags;
@override List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey(name: 'is_nsfw') final  bool isNsfw;
@override final  String? title;
@override final  String? description;
@override@JsonKey(name: 'author_name') final  String? authorName;
@override@JsonKey(name: 'author_id') final  String? authorId;
@override@JsonKey(name: 'author_avatar_url') final  String? authorAvatarUrl;
@override@JsonKey(name: 'cover_url') final  String? coverUrl;
@override@JsonKey(name: 'cover_color') final  String? coverColor;
@override@JsonKey(name: 'created_at') final  DateTime createdAt;
@override@JsonKey(name: 'updated_at') final  DateTime updatedAt;
@override@JsonKey(name: 'published_at') final  DateTime? publishedAt;
 final  List<String> _mediaUrls;
@override@JsonKey(name: 'media_urls') List<String> get mediaUrls {
  if (_mediaUrls is EqualUnmodifiableListView) return _mediaUrls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mediaUrls);
}

@override@JsonKey(name: 'view_count') final  int viewCount;
@override@JsonKey(name: 'like_count') final  int likeCount;
@override@JsonKey(name: 'collect_count') final  int collectCount;
@override@JsonKey(name: 'share_count') final  int shareCount;
@override@JsonKey(name: 'comment_count') final  int commentCount;
 final  Map<String, dynamic> _extraStats;
@override@JsonKey(name: 'extra_stats') Map<String, dynamic> get extraStats {
  if (_extraStats is EqualUnmodifiableMapView) return _extraStats;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_extraStats);
}

 final  Map<String, dynamic>? _rawMetadata;
@override@JsonKey(name: 'raw_metadata') Map<String, dynamic>? get rawMetadata {
  final value = _rawMetadata;
  if (value == null) return null;
  if (_rawMetadata is EqualUnmodifiableMapView) return _rawMetadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ContentDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContentDetailCopyWith<_ContentDetail> get copyWith => __$ContentDetailCopyWithImpl<_ContentDetail>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ContentDetailToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContentDetail&&(identical(other.id, id) || other.id == id)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.platformId, platformId) || other.platformId == platformId)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.url, url) || other.url == url)&&(identical(other.cleanUrl, cleanUrl) || other.cleanUrl == cleanUrl)&&(identical(other.status, status) || other.status == status)&&(identical(other.reviewStatus, reviewStatus) || other.reviewStatus == reviewStatus)&&const DeepCollectionEquality().equals(other._tags, _tags)&&(identical(other.isNsfw, isNsfw) || other.isNsfw == isNsfw)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.authorName, authorName) || other.authorName == authorName)&&(identical(other.authorId, authorId) || other.authorId == authorId)&&(identical(other.authorAvatarUrl, authorAvatarUrl) || other.authorAvatarUrl == authorAvatarUrl)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.coverColor, coverColor) || other.coverColor == coverColor)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&const DeepCollectionEquality().equals(other._mediaUrls, _mediaUrls)&&(identical(other.viewCount, viewCount) || other.viewCount == viewCount)&&(identical(other.likeCount, likeCount) || other.likeCount == likeCount)&&(identical(other.collectCount, collectCount) || other.collectCount == collectCount)&&(identical(other.shareCount, shareCount) || other.shareCount == shareCount)&&(identical(other.commentCount, commentCount) || other.commentCount == commentCount)&&const DeepCollectionEquality().equals(other._extraStats, _extraStats)&&const DeepCollectionEquality().equals(other._rawMetadata, _rawMetadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,platform,platformId,contentType,url,cleanUrl,status,reviewStatus,const DeepCollectionEquality().hash(_tags),isNsfw,title,description,authorName,authorId,authorAvatarUrl,coverUrl,coverColor,createdAt,updatedAt,publishedAt,const DeepCollectionEquality().hash(_mediaUrls),viewCount,likeCount,collectCount,shareCount,commentCount,const DeepCollectionEquality().hash(_extraStats),const DeepCollectionEquality().hash(_rawMetadata)]);

@override
String toString() {
  return 'ContentDetail(id: $id, platform: $platform, platformId: $platformId, contentType: $contentType, url: $url, cleanUrl: $cleanUrl, status: $status, reviewStatus: $reviewStatus, tags: $tags, isNsfw: $isNsfw, title: $title, description: $description, authorName: $authorName, authorId: $authorId, authorAvatarUrl: $authorAvatarUrl, coverUrl: $coverUrl, coverColor: $coverColor, createdAt: $createdAt, updatedAt: $updatedAt, publishedAt: $publishedAt, mediaUrls: $mediaUrls, viewCount: $viewCount, likeCount: $likeCount, collectCount: $collectCount, shareCount: $shareCount, commentCount: $commentCount, extraStats: $extraStats, rawMetadata: $rawMetadata)';
}


}

/// @nodoc
abstract mixin class _$ContentDetailCopyWith<$Res> implements $ContentDetailCopyWith<$Res> {
  factory _$ContentDetailCopyWith(_ContentDetail value, $Res Function(_ContentDetail) _then) = __$ContentDetailCopyWithImpl;
@override @useResult
$Res call({
 int id, String platform,@JsonKey(name: 'platform_id') String? platformId,@JsonKey(name: 'content_type') String? contentType, String url,@JsonKey(name: 'clean_url') String? cleanUrl, String status,@JsonKey(name: 'review_status') String? reviewStatus, List<String> tags,@JsonKey(name: 'is_nsfw') bool isNsfw, String? title, String? description,@JsonKey(name: 'author_name') String? authorName,@JsonKey(name: 'author_id') String? authorId,@JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,@JsonKey(name: 'cover_url') String? coverUrl,@JsonKey(name: 'cover_color') String? coverColor,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'updated_at') DateTime updatedAt,@JsonKey(name: 'published_at') DateTime? publishedAt,@JsonKey(name: 'media_urls') List<String> mediaUrls,@JsonKey(name: 'view_count') int viewCount,@JsonKey(name: 'like_count') int likeCount,@JsonKey(name: 'collect_count') int collectCount,@JsonKey(name: 'share_count') int shareCount,@JsonKey(name: 'comment_count') int commentCount,@JsonKey(name: 'extra_stats') Map<String, dynamic> extraStats,@JsonKey(name: 'raw_metadata') Map<String, dynamic>? rawMetadata
});




}
/// @nodoc
class __$ContentDetailCopyWithImpl<$Res>
    implements _$ContentDetailCopyWith<$Res> {
  __$ContentDetailCopyWithImpl(this._self, this._then);

  final _ContentDetail _self;
  final $Res Function(_ContentDetail) _then;

/// Create a copy of ContentDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? platform = null,Object? platformId = freezed,Object? contentType = freezed,Object? url = null,Object? cleanUrl = freezed,Object? status = null,Object? reviewStatus = freezed,Object? tags = null,Object? isNsfw = null,Object? title = freezed,Object? description = freezed,Object? authorName = freezed,Object? authorId = freezed,Object? authorAvatarUrl = freezed,Object? coverUrl = freezed,Object? coverColor = freezed,Object? createdAt = null,Object? updatedAt = null,Object? publishedAt = freezed,Object? mediaUrls = null,Object? viewCount = null,Object? likeCount = null,Object? collectCount = null,Object? shareCount = null,Object? commentCount = null,Object? extraStats = null,Object? rawMetadata = freezed,}) {
  return _then(_ContentDetail(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,platformId: freezed == platformId ? _self.platformId : platformId // ignore: cast_nullable_to_non_nullable
as String?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,cleanUrl: freezed == cleanUrl ? _self.cleanUrl : cleanUrl // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,reviewStatus: freezed == reviewStatus ? _self.reviewStatus : reviewStatus // ignore: cast_nullable_to_non_nullable
as String?,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,isNsfw: null == isNsfw ? _self.isNsfw : isNsfw // ignore: cast_nullable_to_non_nullable
as bool,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,authorName: freezed == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String?,authorId: freezed == authorId ? _self.authorId : authorId // ignore: cast_nullable_to_non_nullable
as String?,authorAvatarUrl: freezed == authorAvatarUrl ? _self.authorAvatarUrl : authorAvatarUrl // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,coverColor: freezed == coverColor ? _self.coverColor : coverColor // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,publishedAt: freezed == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,mediaUrls: null == mediaUrls ? _self._mediaUrls : mediaUrls // ignore: cast_nullable_to_non_nullable
as List<String>,viewCount: null == viewCount ? _self.viewCount : viewCount // ignore: cast_nullable_to_non_nullable
as int,likeCount: null == likeCount ? _self.likeCount : likeCount // ignore: cast_nullable_to_non_nullable
as int,collectCount: null == collectCount ? _self.collectCount : collectCount // ignore: cast_nullable_to_non_nullable
as int,shareCount: null == shareCount ? _self.shareCount : shareCount // ignore: cast_nullable_to_non_nullable
as int,commentCount: null == commentCount ? _self.commentCount : commentCount // ignore: cast_nullable_to_non_nullable
as int,extraStats: null == extraStats ? _self._extraStats : extraStats // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,rawMetadata: freezed == rawMetadata ? _self._rawMetadata : rawMetadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}


/// @nodoc
mixin _$ContentListResponse {

 List<ContentDetail> get items; int get total; int get page; int get size;@JsonKey(name: 'has_more') bool get hasMore;
/// Create a copy of ContentListResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContentListResponseCopyWith<ContentListResponse> get copyWith => _$ContentListResponseCopyWithImpl<ContentListResponse>(this as ContentListResponse, _$identity);

  /// Serializes this ContentListResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContentListResponse&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.size, size) || other.size == size)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),total,page,size,hasMore);

@override
String toString() {
  return 'ContentListResponse(items: $items, total: $total, page: $page, size: $size, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class $ContentListResponseCopyWith<$Res>  {
  factory $ContentListResponseCopyWith(ContentListResponse value, $Res Function(ContentListResponse) _then) = _$ContentListResponseCopyWithImpl;
@useResult
$Res call({
 List<ContentDetail> items, int total, int page, int size,@JsonKey(name: 'has_more') bool hasMore
});




}
/// @nodoc
class _$ContentListResponseCopyWithImpl<$Res>
    implements $ContentListResponseCopyWith<$Res> {
  _$ContentListResponseCopyWithImpl(this._self, this._then);

  final ContentListResponse _self;
  final $Res Function(ContentListResponse) _then;

/// Create a copy of ContentListResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? total = null,Object? page = null,Object? size = null,Object? hasMore = null,}) {
  return _then(_self.copyWith(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ContentDetail>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ContentListResponse].
extension ContentListResponsePatterns on ContentListResponse {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContentListResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContentListResponse() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContentListResponse value)  $default,){
final _that = this;
switch (_that) {
case _ContentListResponse():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContentListResponse value)?  $default,){
final _that = this;
switch (_that) {
case _ContentListResponse() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ContentDetail> items,  int total,  int page,  int size, @JsonKey(name: 'has_more')  bool hasMore)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContentListResponse() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.size,_that.hasMore);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ContentDetail> items,  int total,  int page,  int size, @JsonKey(name: 'has_more')  bool hasMore)  $default,) {final _that = this;
switch (_that) {
case _ContentListResponse():
return $default(_that.items,_that.total,_that.page,_that.size,_that.hasMore);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ContentDetail> items,  int total,  int page,  int size, @JsonKey(name: 'has_more')  bool hasMore)?  $default,) {final _that = this;
switch (_that) {
case _ContentListResponse() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.size,_that.hasMore);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ContentListResponse implements ContentListResponse {
  const _ContentListResponse({required final  List<ContentDetail> items, required this.total, required this.page, required this.size, @JsonKey(name: 'has_more') required this.hasMore}): _items = items;
  factory _ContentListResponse.fromJson(Map<String, dynamic> json) => _$ContentListResponseFromJson(json);

 final  List<ContentDetail> _items;
@override List<ContentDetail> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int total;
@override final  int page;
@override final  int size;
@override@JsonKey(name: 'has_more') final  bool hasMore;

/// Create a copy of ContentListResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContentListResponseCopyWith<_ContentListResponse> get copyWith => __$ContentListResponseCopyWithImpl<_ContentListResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ContentListResponseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContentListResponse&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.size, size) || other.size == size)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),total,page,size,hasMore);

@override
String toString() {
  return 'ContentListResponse(items: $items, total: $total, page: $page, size: $size, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class _$ContentListResponseCopyWith<$Res> implements $ContentListResponseCopyWith<$Res> {
  factory _$ContentListResponseCopyWith(_ContentListResponse value, $Res Function(_ContentListResponse) _then) = __$ContentListResponseCopyWithImpl;
@override @useResult
$Res call({
 List<ContentDetail> items, int total, int page, int size,@JsonKey(name: 'has_more') bool hasMore
});




}
/// @nodoc
class __$ContentListResponseCopyWithImpl<$Res>
    implements _$ContentListResponseCopyWith<$Res> {
  __$ContentListResponseCopyWithImpl(this._self, this._then);

  final _ContentListResponse _self;
  final $Res Function(_ContentListResponse) _then;

/// Create a copy of ContentListResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? total = null,Object? page = null,Object? size = null,Object? hasMore = null,}) {
  return _then(_ContentListResponse(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ContentDetail>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$ShareCardListResponse {

 List<ShareCard> get items; int get total; int get page; int get size;@JsonKey(name: 'has_more') bool get hasMore;
/// Create a copy of ShareCardListResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShareCardListResponseCopyWith<ShareCardListResponse> get copyWith => _$ShareCardListResponseCopyWithImpl<ShareCardListResponse>(this as ShareCardListResponse, _$identity);

  /// Serializes this ShareCardListResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShareCardListResponse&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.size, size) || other.size == size)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),total,page,size,hasMore);

@override
String toString() {
  return 'ShareCardListResponse(items: $items, total: $total, page: $page, size: $size, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class $ShareCardListResponseCopyWith<$Res>  {
  factory $ShareCardListResponseCopyWith(ShareCardListResponse value, $Res Function(ShareCardListResponse) _then) = _$ShareCardListResponseCopyWithImpl;
@useResult
$Res call({
 List<ShareCard> items, int total, int page, int size,@JsonKey(name: 'has_more') bool hasMore
});




}
/// @nodoc
class _$ShareCardListResponseCopyWithImpl<$Res>
    implements $ShareCardListResponseCopyWith<$Res> {
  _$ShareCardListResponseCopyWithImpl(this._self, this._then);

  final ShareCardListResponse _self;
  final $Res Function(ShareCardListResponse) _then;

/// Create a copy of ShareCardListResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? total = null,Object? page = null,Object? size = null,Object? hasMore = null,}) {
  return _then(_self.copyWith(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ShareCard>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ShareCardListResponse].
extension ShareCardListResponsePatterns on ShareCardListResponse {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShareCardListResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShareCardListResponse() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShareCardListResponse value)  $default,){
final _that = this;
switch (_that) {
case _ShareCardListResponse():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShareCardListResponse value)?  $default,){
final _that = this;
switch (_that) {
case _ShareCardListResponse() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ShareCard> items,  int total,  int page,  int size, @JsonKey(name: 'has_more')  bool hasMore)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShareCardListResponse() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.size,_that.hasMore);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ShareCard> items,  int total,  int page,  int size, @JsonKey(name: 'has_more')  bool hasMore)  $default,) {final _that = this;
switch (_that) {
case _ShareCardListResponse():
return $default(_that.items,_that.total,_that.page,_that.size,_that.hasMore);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ShareCard> items,  int total,  int page,  int size, @JsonKey(name: 'has_more')  bool hasMore)?  $default,) {final _that = this;
switch (_that) {
case _ShareCardListResponse() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.size,_that.hasMore);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ShareCardListResponse implements ShareCardListResponse {
  const _ShareCardListResponse({required final  List<ShareCard> items, required this.total, required this.page, required this.size, @JsonKey(name: 'has_more') required this.hasMore}): _items = items;
  factory _ShareCardListResponse.fromJson(Map<String, dynamic> json) => _$ShareCardListResponseFromJson(json);

 final  List<ShareCard> _items;
@override List<ShareCard> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int total;
@override final  int page;
@override final  int size;
@override@JsonKey(name: 'has_more') final  bool hasMore;

/// Create a copy of ShareCardListResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShareCardListResponseCopyWith<_ShareCardListResponse> get copyWith => __$ShareCardListResponseCopyWithImpl<_ShareCardListResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ShareCardListResponseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShareCardListResponse&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.size, size) || other.size == size)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),total,page,size,hasMore);

@override
String toString() {
  return 'ShareCardListResponse(items: $items, total: $total, page: $page, size: $size, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class _$ShareCardListResponseCopyWith<$Res> implements $ShareCardListResponseCopyWith<$Res> {
  factory _$ShareCardListResponseCopyWith(_ShareCardListResponse value, $Res Function(_ShareCardListResponse) _then) = __$ShareCardListResponseCopyWithImpl;
@override @useResult
$Res call({
 List<ShareCard> items, int total, int page, int size,@JsonKey(name: 'has_more') bool hasMore
});




}
/// @nodoc
class __$ShareCardListResponseCopyWithImpl<$Res>
    implements _$ShareCardListResponseCopyWith<$Res> {
  __$ShareCardListResponseCopyWithImpl(this._self, this._then);

  final _ShareCardListResponse _self;
  final $Res Function(_ShareCardListResponse) _then;

/// Create a copy of ShareCardListResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? total = null,Object? page = null,Object? size = null,Object? hasMore = null,}) {
  return _then(_ShareCardListResponse(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ShareCard>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
