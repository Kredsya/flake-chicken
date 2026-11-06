# Room 2.6.x loads generated database implementations through reflection.
# R8 full mode needs the zero-argument constructor kept explicitly.
# Upstream fix: https://android.googlesource.com/platform/frameworks/support/+/e4765e38e27a3f4d86188b996df97a52403dff46
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
