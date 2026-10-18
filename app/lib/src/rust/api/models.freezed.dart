// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ScanEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ScanEvent()';
}


}

/// @nodoc
class $ScanEventCopyWith<$Res>  {
$ScanEventCopyWith(ScanEvent _, $Res Function(ScanEvent) __);
}


/// Adds pattern-matching-related methods to [ScanEvent].
extension ScanEventPatterns on ScanEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ScanEvent_Started value)?  started,TResult Function( ScanEvent_Progress value)?  progress,TResult Function( ScanEvent_Finished value)?  finished,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ScanEvent_Started() when started != null:
return started(_that);case ScanEvent_Progress() when progress != null:
return progress(_that);case ScanEvent_Finished() when finished != null:
return finished(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ScanEvent_Started value)  started,required TResult Function( ScanEvent_Progress value)  progress,required TResult Function( ScanEvent_Finished value)  finished,}){
final _that = this;
switch (_that) {
case ScanEvent_Started():
return started(_that);case ScanEvent_Progress():
return progress(_that);case ScanEvent_Finished():
return finished(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ScanEvent_Started value)?  started,TResult? Function( ScanEvent_Progress value)?  progress,TResult? Function( ScanEvent_Finished value)?  finished,}){
final _that = this;
switch (_that) {
case ScanEvent_Started() when started != null:
return started(_that);case ScanEvent_Progress() when progress != null:
return progress(_that);case ScanEvent_Finished() when finished != null:
return finished(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int total)?  started,TResult Function( int done,  int total,  String current)?  progress,TResult Function( List<AlbumSummary> albums,  PlatformInt64 elapsedMs,  int rescanned)?  finished,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ScanEvent_Started() when started != null:
return started(_that.total);case ScanEvent_Progress() when progress != null:
return progress(_that.done,_that.total,_that.current);case ScanEvent_Finished() when finished != null:
return finished(_that.albums,_that.elapsedMs,_that.rescanned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int total)  started,required TResult Function( int done,  int total,  String current)  progress,required TResult Function( List<AlbumSummary> albums,  PlatformInt64 elapsedMs,  int rescanned)  finished,}) {final _that = this;
switch (_that) {
case ScanEvent_Started():
return started(_that.total);case ScanEvent_Progress():
return progress(_that.done,_that.total,_that.current);case ScanEvent_Finished():
return finished(_that.albums,_that.elapsedMs,_that.rescanned);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int total)?  started,TResult? Function( int done,  int total,  String current)?  progress,TResult? Function( List<AlbumSummary> albums,  PlatformInt64 elapsedMs,  int rescanned)?  finished,}) {final _that = this;
switch (_that) {
case ScanEvent_Started() when started != null:
return started(_that.total);case ScanEvent_Progress() when progress != null:
return progress(_that.done,_that.total,_that.current);case ScanEvent_Finished() when finished != null:
return finished(_that.albums,_that.elapsedMs,_that.rescanned);case _:
  return null;

}
}

}

/// @nodoc


class ScanEvent_Started extends ScanEvent {
  const ScanEvent_Started({required this.total}): super._();
  

 final  int total;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanEvent_StartedCopyWith<ScanEvent_Started> get copyWith => _$ScanEvent_StartedCopyWithImpl<ScanEvent_Started>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent_Started&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,total);
}

@override
String toString() {
    return 'ScanEvent.started(total: $total)';
}


}

/// @nodoc
abstract mixin class $ScanEvent_StartedCopyWith<$Res> implements $ScanEventCopyWith<$Res> {
  factory $ScanEvent_StartedCopyWith(ScanEvent_Started value, $Res Function(ScanEvent_Started) _then) = _$ScanEvent_StartedCopyWithImpl;
@useResult
$Res call({
 int total
});




}
/// @nodoc
class _$ScanEvent_StartedCopyWithImpl<$Res>
    implements $ScanEvent_StartedCopyWith<$Res> {
  _$ScanEvent_StartedCopyWithImpl(this._self, this._then);

  final ScanEvent_Started _self;
  final $Res Function(ScanEvent_Started) _then;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? total = null,}) {
  return _then(ScanEvent_Started(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ScanEvent_Progress extends ScanEvent {
  const ScanEvent_Progress({required this.done, required this.total, required this.current}): super._();
  

 final  int done;
 final  int total;
 final  String current;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanEvent_ProgressCopyWith<ScanEvent_Progress> get copyWith => _$ScanEvent_ProgressCopyWithImpl<ScanEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent_Progress&&(identical(other.done, done) || other.done == done)&&(identical(other.total, total) || other.total == total)&&(identical(other.current, current) || other.current == current));
}


@override
int get hashCode {
    return Object.hash(runtimeType,done,total,current);
}

@override
String toString() {
    return 'ScanEvent.progress(done: $done, total: $total, current: $current)';
}


}

/// @nodoc
abstract mixin class $ScanEvent_ProgressCopyWith<$Res> implements $ScanEventCopyWith<$Res> {
  factory $ScanEvent_ProgressCopyWith(ScanEvent_Progress value, $Res Function(ScanEvent_Progress) _then) = _$ScanEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 int done, int total, String current
});




}
/// @nodoc
class _$ScanEvent_ProgressCopyWithImpl<$Res>
    implements $ScanEvent_ProgressCopyWith<$Res> {
  _$ScanEvent_ProgressCopyWithImpl(this._self, this._then);

  final ScanEvent_Progress _self;
  final $Res Function(ScanEvent_Progress) _then;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? done = null,Object? total = null,Object? current = null,}) {
  return _then(ScanEvent_Progress(
done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ScanEvent_Finished extends ScanEvent {
  const ScanEvent_Finished({required  List<AlbumSummary> albums, required this.elapsedMs, required this.rescanned}): _albums = albums,super._();
  

 final  List<AlbumSummary> _albums;
 List<AlbumSummary> get albums {
  if (_albums is EqualUnmodifiableListView) return _albums;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_albums);
}

 final  PlatformInt64 elapsedMs;
 final  int rescanned;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanEvent_FinishedCopyWith<ScanEvent_Finished> get copyWith => _$ScanEvent_FinishedCopyWithImpl<ScanEvent_Finished>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent_Finished&&const DeepCollectionEquality().equals(other.albums, _albums)&&(identical(other.elapsedMs, elapsedMs) || other.elapsedMs == elapsedMs)&&(identical(other.rescanned, rescanned) || other.rescanned == rescanned));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_albums),elapsedMs,rescanned);
}

@override
String toString() {
    return 'ScanEvent.finished(albums: $albums, elapsedMs: $elapsedMs, rescanned: $rescanned)';
}


}

/// @nodoc
abstract mixin class $ScanEvent_FinishedCopyWith<$Res> implements $ScanEventCopyWith<$Res> {
  factory $ScanEvent_FinishedCopyWith(ScanEvent_Finished value, $Res Function(ScanEvent_Finished) _then) = _$ScanEvent_FinishedCopyWithImpl;
@useResult
$Res call({
 List<AlbumSummary> albums, PlatformInt64 elapsedMs, int rescanned
});




}
/// @nodoc
class _$ScanEvent_FinishedCopyWithImpl<$Res>
    implements $ScanEvent_FinishedCopyWith<$Res> {
  _$ScanEvent_FinishedCopyWithImpl(this._self, this._then);

  final ScanEvent_Finished _self;
  final $Res Function(ScanEvent_Finished) _then;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? albums = null,Object? elapsedMs = null,Object? rescanned = null,}) {
  return _then(ScanEvent_Finished(
albums: null == albums ? _self._albums : albums // ignore: cast_nullable_to_non_nullable
as List<AlbumSummary>,elapsedMs: null == elapsedMs ? _self.elapsedMs : elapsedMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64,rescanned: null == rescanned ? _self.rescanned : rescanned // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
