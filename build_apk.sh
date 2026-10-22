#!/bin/bash
set -e

# Override any of these from the environment, e.g.
#   ANDROID_SDK=$HOME/Android/Sdk ./build_apk.sh
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
ANDROID_SDK="${ANDROID_SDK:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
SDK_TOOLS="${SDK_TOOLS:-$ANDROID_SDK/build-tools/34.0.0}"
PLATFORM_JAR="${PLATFORM_JAR:-$ANDROID_SDK/platforms/android-34/android.jar}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build}"
OUT_APK="${OUT_APK:-$PROJECT_DIR/build/OneLineage.apk}"
[ -n "$JAVA_HOME" ] && export PATH="$JAVA_HOME/bin:$PATH"

# Tools default to the SDK binaries; each can be overridden (e.g. on Linux with a
# Windows SDK: AAPT2=<linux aapt2>, D8="java -cp .../lib/d8.jar com.android.tools.r8.D8",
# APKSIGNER="java -jar .../lib/apksigner.jar", ZIPALIGN="python3 tools/zipalign.py").
AAPT2="${AAPT2:-$SDK_TOOLS/aapt2}"
D8="${D8:-$SDK_TOOLS/d8}"
APKSIGNER="${APKSIGNER:-$SDK_TOOLS/apksigner}"
ZIPALIGN="${ZIPALIGN:-$SDK_TOOLS/zipalign -p 4}"

for f in "$PLATFORM_JAR"; do
    [ -e "$f" ] || { echo "missing: $f (set ANDROID_SDK / SDK_TOOLS / PLATFORM_JAR)"; exit 1; }
done

echo "=== 1. Cleaning & preparing build directories ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/gen" "$BUILD_DIR/classes" "$BUILD_DIR/dex"

cd "$PROJECT_DIR"

echo "=== 2. Compiling resources with aapt2 ==="
$AAPT2 compile --dir res -o "$BUILD_DIR/compiled_res.zip"

echo "=== 3. Linking resources with aapt2 ==="
$AAPT2 link \
    -I "$PLATFORM_JAR" \
    --manifest AndroidManifest.xml \
    -o "$BUILD_DIR/base.apk" \
    --java "$BUILD_DIR/gen" \
    "$BUILD_DIR/compiled_res.zip" \
    -A assets

echo "=== 4. Compiling Java sources ==="
javac --release 8 \
    -cp "$PLATFORM_JAR" \
    -d "$BUILD_DIR/classes" \
    src/com/wewaffles/onelineage/MainActivity.java \
    "$BUILD_DIR/gen/com/wewaffles/onelineage/R.java"

echo "=== 5. Generating Dalvik Executable (classes.dex) with d8 ==="
$D8 \
    --lib "$PLATFORM_JAR" \
    --output "$BUILD_DIR/dex" \
    "$BUILD_DIR/classes/com/wewaffles/onelineage"/*.class

echo "=== 6. Packaging classes.dex into APK ==="
cd "$BUILD_DIR/dex"
zip -u "$BUILD_DIR/base.apk" classes.dex
cd "$PROJECT_DIR"

echo "=== 7. Aligning APK with zipalign ==="
$ZIPALIGN "$BUILD_DIR/base.apk" "$BUILD_DIR/aligned.apk"

KEYSTORE="$PROJECT_DIR/keystore/debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
    mkdir -p "$PROJECT_DIR/keystore"
    keytool -genkey -v \
        -keystore "$KEYSTORE" \
        -storepass android \
        -alias androiddebugkey \
        -keypass android \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -dname "CN=OneLineage,O=WeWaffles,C=US"
fi

$APKSIGNER sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:android \
    --ks-key-alias androiddebugkey \
    --key-pass pass:android \
    --out "$OUT_APK" \
    "$BUILD_DIR/aligned.apk"

echo "=== BUILD SUCCESSFUL ==="
echo "Output APK: $OUT_APK"
ls -la "$OUT_APK"
