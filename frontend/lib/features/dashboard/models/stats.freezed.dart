// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'stats.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$QueueStats {

 int get pending; int get processing; int get failed; int get archived; int get total;
/// Create a copy of QueueStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueStatsCopyWith<QueueStats> get copyWith => _$QueueStatsCopyWithImpl<QueueStats>(this as QueueStats, _$identity);

  /// Serializes this QueueStats to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueStats&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.processing, processing) || other.processing == processing)&&(identical(other.failed, failed) || other.failed == failed)&&(identical(other.archived, archived) || other.archived == archived)&&(identical(other.total, total) || other.total == total));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,pending,processing,failed,archived,total);

@override
String toString() {
  return 'QueueStats(pending: $pending, processing: $processing, failed: $failed, archived: $archived, total: $total)';
}


}

/// @nodoc
abstract mixin class $QueueStatsCopyWith<$Res>  {
  factory $QueueStatsCopyWith(QueueStats value, $Res Function(QueueStats) _then) = _$QueueStatsCopyWithImpl;
@useResult
$Res call({
 int pending, int processing, int failed, int archived, int total
});




}
/// @nodoc
class _$QueueStatsCopyWithImpl<$Res>
    implements $QueueStatsCopyWith<$Res> {
  _$QueueStatsCopyWithImpl(this._self, this._then);

  final QueueStats _self;
  final $Res Function(QueueStats) _then;

/// Create a copy of QueueStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pending = null,Object? processing = null,Object? failed = null,Object? archived = null,Object? total = null,}) {
  return _then(_self.copyWith(
pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as int,processing: null == processing ? _self.processing : processing // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [QueueStats].
extension QueueStatsPatterns on QueueStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QueueStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QueueStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QueueStats value)  $default,){
final _that = this;
switch (_that) {
case _QueueStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QueueStats value)?  $default,){
final _that = this;
switch (_that) {
case _QueueStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int pending,  int processing,  int failed,  int archived,  int total)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QueueStats() when $default != null:
return $default(_that.pending,_that.processing,_that.failed,_that.archived,_that.total);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int pending,  int processing,  int failed,  int archived,  int total)  $default,) {final _that = this;
switch (_that) {
case _QueueStats():
return $default(_that.pending,_that.processing,_that.failed,_that.archived,_that.total);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int pending,  int processing,  int failed,  int archived,  int total)?  $default,) {final _that = this;
switch (_that) {
case _QueueStats() when $default != null:
return $default(_that.pending,_that.processing,_that.failed,_that.archived,_that.total);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QueueStats implements QueueStats {
  const _QueueStats({required this.pending, required this.processing, required this.failed, required this.archived, required this.total});
  factory _QueueStats.fromJson(Map<String, dynamic> json) => _$QueueStatsFromJson(json);

@override final  int pending;
@override final  int processing;
@override final  int failed;
@override final  int archived;
@override final  int total;

/// Create a copy of QueueStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QueueStatsCopyWith<_QueueStats> get copyWith => __$QueueStatsCopyWithImpl<_QueueStats>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QueueStatsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _QueueStats&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.processing, processing) || other.processing == processing)&&(identical(other.failed, failed) || other.failed == failed)&&(identical(other.archived, archived) || other.archived == archived)&&(identical(other.total, total) || other.total == total));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,pending,processing,failed,archived,total);

@override
String toString() {
  return 'QueueStats(pending: $pending, processing: $processing, failed: $failed, archived: $archived, total: $total)';
}


}

/// @nodoc
abstract mixin class _$QueueStatsCopyWith<$Res> implements $QueueStatsCopyWith<$Res> {
  factory _$QueueStatsCopyWith(_QueueStats value, $Res Function(_QueueStats) _then) = __$QueueStatsCopyWithImpl;
@override @useResult
$Res call({
 int pending, int processing, int failed, int archived, int total
});




}
/// @nodoc
class __$QueueStatsCopyWithImpl<$Res>
    implements _$QueueStatsCopyWith<$Res> {
  __$QueueStatsCopyWithImpl(this._self, this._then);

  final _QueueStats _self;
  final $Res Function(_QueueStats) _then;

/// Create a copy of QueueStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pending = null,Object? processing = null,Object? failed = null,Object? archived = null,Object? total = null,}) {
  return _then(_QueueStats(
pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as int,processing: null == processing ? _self.processing : processing // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,archived: null == archived ? _self.archived : archived // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$DashboardStats {

@JsonKey(name: 'platform_counts') Map<String, int> get platformCounts;@JsonKey(name: 'daily_growth') List<Map<String, dynamic>> get dailyGrowth;@JsonKey(name: 'storage_usage_bytes') int get storageUsageBytes;
/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DashboardStatsCopyWith<DashboardStats> get copyWith => _$DashboardStatsCopyWithImpl<DashboardStats>(this as DashboardStats, _$identity);

  /// Serializes this DashboardStats to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DashboardStats&&const DeepCollectionEquality().equals(other.platformCounts, platformCounts)&&const DeepCollectionEquality().equals(other.dailyGrowth, dailyGrowth)&&(identical(other.storageUsageBytes, storageUsageBytes) || other.storageUsageBytes == storageUsageBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(platformCounts),const DeepCollectionEquality().hash(dailyGrowth),storageUsageBytes);

@override
String toString() {
  return 'DashboardStats(platformCounts: $platformCounts, dailyGrowth: $dailyGrowth, storageUsageBytes: $storageUsageBytes)';
}


}

/// @nodoc
abstract mixin class $DashboardStatsCopyWith<$Res>  {
  factory $DashboardStatsCopyWith(DashboardStats value, $Res Function(DashboardStats) _then) = _$DashboardStatsCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'platform_counts') Map<String, int> platformCounts,@JsonKey(name: 'daily_growth') List<Map<String, dynamic>> dailyGrowth,@JsonKey(name: 'storage_usage_bytes') int storageUsageBytes
});




}
/// @nodoc
class _$DashboardStatsCopyWithImpl<$Res>
    implements $DashboardStatsCopyWith<$Res> {
  _$DashboardStatsCopyWithImpl(this._self, this._then);

  final DashboardStats _self;
  final $Res Function(DashboardStats) _then;

/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? platformCounts = null,Object? dailyGrowth = null,Object? storageUsageBytes = null,}) {
  return _then(_self.copyWith(
platformCounts: null == platformCounts ? _self.platformCounts : platformCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,dailyGrowth: null == dailyGrowth ? _self.dailyGrowth : dailyGrowth // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,storageUsageBytes: null == storageUsageBytes ? _self.storageUsageBytes : storageUsageBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DashboardStats].
extension DashboardStatsPatterns on DashboardStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DashboardStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DashboardStats value)  $default,){
final _that = this;
switch (_that) {
case _DashboardStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DashboardStats value)?  $default,){
final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'platform_counts')  Map<String, int> platformCounts, @JsonKey(name: 'daily_growth')  List<Map<String, dynamic>> dailyGrowth, @JsonKey(name: 'storage_usage_bytes')  int storageUsageBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
return $default(_that.platformCounts,_that.dailyGrowth,_that.storageUsageBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'platform_counts')  Map<String, int> platformCounts, @JsonKey(name: 'daily_growth')  List<Map<String, dynamic>> dailyGrowth, @JsonKey(name: 'storage_usage_bytes')  int storageUsageBytes)  $default,) {final _that = this;
switch (_that) {
case _DashboardStats():
return $default(_that.platformCounts,_that.dailyGrowth,_that.storageUsageBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'platform_counts')  Map<String, int> platformCounts, @JsonKey(name: 'daily_growth')  List<Map<String, dynamic>> dailyGrowth, @JsonKey(name: 'storage_usage_bytes')  int storageUsageBytes)?  $default,) {final _that = this;
switch (_that) {
case _DashboardStats() when $default != null:
return $default(_that.platformCounts,_that.dailyGrowth,_that.storageUsageBytes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DashboardStats implements DashboardStats {
  const _DashboardStats({@JsonKey(name: 'platform_counts') required final  Map<String, int> platformCounts, @JsonKey(name: 'daily_growth') required final  List<Map<String, dynamic>> dailyGrowth, @JsonKey(name: 'storage_usage_bytes') required this.storageUsageBytes}): _platformCounts = platformCounts,_dailyGrowth = dailyGrowth;
  factory _DashboardStats.fromJson(Map<String, dynamic> json) => _$DashboardStatsFromJson(json);

 final  Map<String, int> _platformCounts;
@override@JsonKey(name: 'platform_counts') Map<String, int> get platformCounts {
  if (_platformCounts is EqualUnmodifiableMapView) return _platformCounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_platformCounts);
}

 final  List<Map<String, dynamic>> _dailyGrowth;
@override@JsonKey(name: 'daily_growth') List<Map<String, dynamic>> get dailyGrowth {
  if (_dailyGrowth is EqualUnmodifiableListView) return _dailyGrowth;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_dailyGrowth);
}

@override@JsonKey(name: 'storage_usage_bytes') final  int storageUsageBytes;

/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DashboardStatsCopyWith<_DashboardStats> get copyWith => __$DashboardStatsCopyWithImpl<_DashboardStats>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DashboardStatsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DashboardStats&&const DeepCollectionEquality().equals(other._platformCounts, _platformCounts)&&const DeepCollectionEquality().equals(other._dailyGrowth, _dailyGrowth)&&(identical(other.storageUsageBytes, storageUsageBytes) || other.storageUsageBytes == storageUsageBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_platformCounts),const DeepCollectionEquality().hash(_dailyGrowth),storageUsageBytes);

@override
String toString() {
  return 'DashboardStats(platformCounts: $platformCounts, dailyGrowth: $dailyGrowth, storageUsageBytes: $storageUsageBytes)';
}


}

/// @nodoc
abstract mixin class _$DashboardStatsCopyWith<$Res> implements $DashboardStatsCopyWith<$Res> {
  factory _$DashboardStatsCopyWith(_DashboardStats value, $Res Function(_DashboardStats) _then) = __$DashboardStatsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'platform_counts') Map<String, int> platformCounts,@JsonKey(name: 'daily_growth') List<Map<String, dynamic>> dailyGrowth,@JsonKey(name: 'storage_usage_bytes') int storageUsageBytes
});




}
/// @nodoc
class __$DashboardStatsCopyWithImpl<$Res>
    implements _$DashboardStatsCopyWith<$Res> {
  __$DashboardStatsCopyWithImpl(this._self, this._then);

  final _DashboardStats _self;
  final $Res Function(_DashboardStats) _then;

/// Create a copy of DashboardStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? platformCounts = null,Object? dailyGrowth = null,Object? storageUsageBytes = null,}) {
  return _then(_DashboardStats(
platformCounts: null == platformCounts ? _self._platformCounts : platformCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,dailyGrowth: null == dailyGrowth ? _self._dailyGrowth : dailyGrowth // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,storageUsageBytes: null == storageUsageBytes ? _self.storageUsageBytes : storageUsageBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
