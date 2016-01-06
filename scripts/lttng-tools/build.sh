#!/bin/bash -xue
#
# Copyright (C) 2015 - Jonathan Rajotte-Julien <jonathan.rajotte-julien@efficios.com>
#                      Michael Jeanson <mjeanson@efficios.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Version compare functions
verlte() {
    [  "$1" = "`printf '%s\n%s' $1 $2 | sort -V | head -n1`" ]
}

verlt() {
    [ "$1" = "$2" ] && return 1 || verlte $1 $2
}

vergte() {
    [  "$1" = "`printf '%s\n%s' $1 $2 | sort -V | tail -n1`" ]
}

vergt() {
    [ "$1" = "$2" ] && return 1 || vergte $1 $2
}


# Create build directory
rm -rf $WORKSPACE/build
mkdir -p $WORKSPACE/build

# liburcu
URCU_INCS="$WORKSPACE/deps/liburcu/build/include/"
URCU_LIBS="$WORKSPACE/deps/liburcu/build/lib/"

# lttng-ust
UST_INCS="$WORKSPACE/deps/lttng-ust/build/include/"
UST_LIBS="$WORKSPACE/deps/lttng-ust/build/lib/"
UST_JAVA="$WORKSPACE/deps/lttng-ust/build/share/java/"

# babeltrace
BABEL_INCS="$WORKSPACE/deps/babeltrace/build/include/"
BABEL_LIBS="$WORKSPACE/deps/babeltrace/build/lib/"
BABEL_BINS="$WORKSPACE/deps/babeltrace/build/bin/"

PREFIX="$WORKSPACE/build"

# Set platform variables
case "$arch" in
solaris10)
    MAKE=gmake
    TAR=gtar
    NPROC=gnproc
    BISON="bison"
    YACC="$BISON -y"
    CFLAGS="-D_XOPEN_SOURCE=1 -D_XOPEN_SOURCE_EXTENDED=1 -D__EXTENSIONS__=1"
    RUN_TESTS="no"
    ;;

solaris11)
    MAKE=gmake
    TAR=gtar
    NPROC=nproc
    BISON="/opt/csw/bin/bison"
    YACC="$BISON -y"
    CFLAGS="-D_XOPEN_SOURCE=1 -D_XOPEN_SOURCE_EXTENDED=1 -D__EXTENSIONS__=1"
    RUN_TESTS="no"

    export PATH="$PATH:/usr/perl5/bin"
    ;;

*)
    MAKE=make
    TAR=tar
    NPROC=nproc
    BISON="bison"
    YACC="$BISON -y"
    CFLAGS=""
    RUN_TESTS="yes"

    PYTHON2=python2
    PYTHON3=python3

    P2_VERSION=$($PYTHON2 -c "import sys;print(sys.version[:3])")
    P3_VERSION=$($PYTHON3 -c "import sys;print(sys.version[:3])")

    UST_PYTHON2="$WORKSPACE/deps/lttng-ust/build/lib/python$P2_VERSION/site-packages"
    UST_PYTHON3="$WORKSPACE/deps/lttng-ust/build/lib/python$P3_VERSION/site-packages"
    ;;
esac


# Run bootstrap prior to configure
./bootstrap

# Get source version from configure script
eval `grep '^PACKAGE_VERSION=' ./configure`


# Export build flags
case "$conf" in
no-ust)
    export CPPFLAGS="-I$URCU_INCS"
    export LDFLAGS="-L$URCU_LIBS"
    export LD_LIBRARY_PATH="$URCU_LIBS:$BABEL_LIBS:${LD_LIBRARY_PATH:-}"
    ;;

*)
    export CPPFLAGS="-I$URCU_INCS -I$UST_INCS"
    export LDFLAGS="-L$URCU_LIBS -L$UST_LIBS"
    export LD_LIBRARY_PATH="$URCU_LIBS:$UST_LIBS:$BABEL_LIBS:${LD_LIBRARY_PATH:-}"
    ;;
esac

# The switch to build without UST changed in 2.8
if vergte "$PACKAGE_VERSION" "2.8"; then
    NO_UST="--without-lttng-ust"
else
    NO_UST="--disable-lttng-ust"
fi

# Set configure options for each build configuration
CONF_OPTS=""
case "$conf" in
static)
    echo "Static build"
    CONF_OPTS="--enable-static --disable-shared"
    ;;

python-bindings)
    echo "Build with python bindings"
    # We only support bindings built with Python 3
    export PYTHON="python3"
    export PYTHON_CONFIG="/usr/bin/python3-config"
    CONF_OPTS="--enable-python-bindings"
    ;;

no-ust)
    echo "Build without UST support"
    CONF_OPTS="$NO_UST"
    ;;

java-agent)
    echo "Build with Java Agents"
    export JAVA_HOME="/usr/lib/jvm/default-java"
    export CLASSPATH="$UST_JAVA/*:/usr/share/java/*"
    CONF_OPTS="--enable-test-java-agent-all"
    ;;

python-agent)
    echo "Build with python agents"
    export PYTHONPATH="$UST_PYTHON2:$UST_PYTHON3"
    CONF_OPTS="--enable-test-python-agent-all"
    ;;

relayd-only)
    echo "Build relayd only"
    CONF_OPTS="--disable-bin-lttng --disable-bin-lttng-consumerd --disable-bin-lttng-crash --disable-bin-lttng-sessiond --disable-extras $NO_UST"
    ;;

*)
    echo "Standard build"
    CONF_OPTS=""
    ;;
esac


# Build type
# oot : out-of-tree build
# dist: build via make dist
# *   : normal tree build
#
# Make sure to move to the build_path and run configure
# before continuing
BUILD_PATH=$WORKSPACE
case "$build" in
    oot)
        echo "Out of tree build"
        BUILD_PATH=$WORKSPACE/oot
        mkdir -p $BUILD_PATH
        cd $BUILD_PATH
        MAKE=$MAKE BISON="$BISON" YACC="$YACC" CFLAGS="$CFLAGS" $WORKSPACE/configure --prefix=$PREFIX $CONF_OPTS
        ;;

    dist)
        echo "Distribution out of tree build"
        BUILD_PATH=`mktemp -d`

        # Initial configure and generate tarball
        MAKE=$MAKE BISON="$BISON" YACC="$YACC" CFLAGS="$CFLAGS" ./configure $CONF_OPTS
        $MAKE dist

        mkdir -p $BUILD_PATH
        cp *.tar.* $BUILD_PATH/
        cd $BUILD_PATH

        # Ignore level 1 of tar
        $TAR xvf *.tar.* --strip 1

        MAKE=$MAKE BISON="$BISON" YACC="$YACC" CFLAGS="$CFLAGS" $BUILD_PATH/configure --prefix=$PREFIX $CONF_OPTS
        ;;

    *)
        BUILD_PATH=$WORKSPACE
        echo "Standard tree build"
        MAKE=$MAKE BISON="$BISON" YACC="$YACC" CFLAGS="$CFLAGS" $WORKSPACE/configure --prefix=$PREFIX $CONF_OPTS
        ;;
esac

# BUILD!
$MAKE -j `$NPROC` V=1
$MAKE install

# Run tests
if [ "$RUN_TESTS" = "yes" ]; then
    # Allow core dumps
    ulimit -c unlimited

    # Add 'babeltrace' binary to PATH
    chmod +x $BABEL_BINS/babeltrace
    export PATH="$PATH:$BABEL_BINS"

    # Prepare tap output dirs
    rm -rf $WORKSPACE/tap
    mkdir -p $WORKSPACE/tap
    mkdir -p $WORKSPACE/tap/unit
    mkdir -p $WORKSPACE/tap/fast_regression
    mkdir -p $WORKSPACE/tap/with_bindings_regression

    cd $BUILD_PATH/tests

    # Run 'unit_tests' and 'fast_regression' test suites for all configs except 'no-ust'
    if [ "$conf" != "no-ust" ]; then
        prove --merge -v --exec '' - < $BUILD_PATH/tests/unit_tests --archive $WORKSPACE/tap/unit/ || true
        prove --merge -v --exec '' - < $BUILD_PATH/tests/fast_regression --archive $WORKSPACE/tap/fast_regression/ || true
    else
        # Regression is disabled for now, we need to adjust the testsuite for no ust builds.
        echo "Testsuite disabled for 'no-ust'. See job configuration for more info."
    fi

    # Run 'with_bindings_regression' test suite for 'python-bindings' config
    if [ "$conf" = "python-bindings" ]; then
        prove --merge -v --exec '' - < $WORKSPACE/tests/with_bindings_regression --archive $WORKSPACE/tap/with_bindings_regression/ || true
    fi

    # TAP plugin is having a hard time with .yml files.
    rm -f $WORKSPACE/tap/unit/meta.yml
    rm -f $WORKSPACE/tap/fast_regression/meta.yml
    rm -f $WORKSPACE/tap/with_bindings_regression/meta.yml

    # And also with files without extension, so rename all result to *.tap
    find $WORKSPACE/tap/unit/ -type f -exec mv {} {}.tap \;
    find $WORKSPACE/tap/fast_regression/ -type f -exec mv {} {}.tap \;
    find $WORKSPACE/tap/with_bindings_regression/ -type f -exec mv {} {}.tap \;
fi

# Cleanup
$MAKE clean

# Cleanup rpath in executables and shared libraries
find $WORKSPACE/build/bin -type f -perm -0500 -exec chrpath --delete {} \;
find $WORKSPACE/build/lib -name "*.so" -exec chrpath --delete {} \;

# Remove libtool .la files
find $WORKSPACE/build/lib -name "*.la" -exec rm -f {} \;

# Clean temp dir for dist build
if [ "$build" = "dist" ]; then
    cd $WORKSPACE
    rm -rf $BUILD_PATH
fi

# EOF