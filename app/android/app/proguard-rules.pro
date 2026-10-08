# 広告 SDK が引き込む WorkManager (androidx.work) の WorkDatabase は Room が生成する実装クラスを
# リフレクションで new する。R8 がそのコンストラクタを消すと起動直後に落ちるので残す。
-keep class * extends androidx.room.RoomDatabase { <init>(); }
