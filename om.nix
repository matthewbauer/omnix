# This file will generate the Omnix derivation. The generation takes a long time
# so you should probably use premade onces.

{ stdenv, runCommand, nix-index, nixStable, jq, curl, bash }:

let

  makeNixIndex = nixpkgs: runCommand "nix-index-db" {
    buildInputs = [ nix-index nixStable ];
    inherit nixpkgs;
    NIX_REMOTE = builtins.getEnv "NIX_REMOTE";
  } ''
mkdir $out
nix-index -d $out -f $nixpkgs 2> /dev/null
  '';

  findApps = db: runCommand "apps" {
    buildInputs = [ nix-index ];
    inherit db;
  } (''
mkdir -p $out
locate="nix-locate -d $db -w --top-level --at-root --no-group"

(
'' + stdenv.lib.optionalString stdenv.isLinux ''
  $locate -t d /share/applications
'' + stdenv.lib.optionalString stdenv.isDarwin ''
  $locate -t d /Applications
'' + '') | sed 's/,//g' | sed -E 's/ +/,/g' | sort -u -t, -k1,1 > $out/apps

$locate -t x -r '/bin/[a-z-_]+' | sed 's/,//g' | sed -E 's/ +/,/g' > $out/bins
  '');

  omnix = { nixpkgs ? <nixos>,
            apps ? findApps (makeNixIndex nixpkgs) }:
  stdenv.mkDerivation rec {
    name = "omnix";

    inherit nixpkgs apps;

    buildInputs = [ nixStable curl ];
    unpackPhase = "true";

    NIX_CACHE="http://cache.nixos.org";

    installPhase = ''
# Install wrapper
mkdir -p $out/share/omnix
cp ${./omnix.sh} $out/share/omnix/omnix.sh
wrapper=$out/share/omnix/omnix.sh

sh=${bash}/bin/sh

# Setup app directories
'' + stdenv.lib.optionalString stdenv.isLinux ''
mkdir -p $out/share/applications
mkdir -p $out/share/icons
'' + stdenv.lib.optionalString stdenv.isDarwin ''
mkdir -p $out/Applications
'' + ''
mkdir -p $out/bin
# Get all of the binaries
cat $apps/bins | while read line; do
  attr=$(echo "$line" | cut -d, -f1)
  path=$(echo "$line" | cut -d, -f4)

  name=$(basename $path)

  if [ -x "$out/bin/$name" ]; then continue; fi

  cat <<EOF >$out/bin/$name
#!$sh
$wrapper $nixpkgs $attr bin/$name '%s %s' \$@

EOF
  chmod +x $out/bin/$name
done

# Get application metadata
cat $apps/apps | while read line; do
  attr=$(echo "$line" | cut -d, -f1)
  path=$(echo "$line" | cut -d, -f4)

  hash=$(echo "$path" | sed -E 's;^/nix/store/([^-]+).*$;\1;')

  if [ -d "$hash" ]; then continue; fi

  path=$(curl "$NIX_CACHE/$hash.narinfo" | grep '^URL: ' | \
                                           sed 's/^URL: \(.*\)/\1/')

  curl "$NIX_CACHE/$path" | xzcat | nix-store --restore $hash
  cd $hash
'' + stdenv.lib.optionalString stdenv.isLinux ''
  if [ -d share/applications ]; then
    cp -RT share/applications $out/share/applications
  fi

  if [ -d share/mime ]; then
    cp -RT share/mime $out/share/mime
  fi

  if [ -d share/icons ]; then
    cp -RT share/icons $out/share/icons
  fi
'' + stdenv.lib.optionalString stdenv.isDarwin ''
  if [ -d Applications ]; then
    for appdir in Applications/*; do
      name=$(basename "$appdir" | sed 's/\.app$//')
      if [ -d "$out/Applications/$name.app" ]; then continue; fi

      mkdir -p "$out/Applications/$name.app/Contents/MacOS"
      cat <<EOF >"$out/Applications/$name.app/Contents/MacOS/$name"
#!$sh
$wrapper $nixpkgs $attr Applications/$name.app/Contents/MacOS/$name '%s %s' \$@

EOF
      chmod +x "$out/Applications/$name.app/Contents/MacOS/$name"

      cp "$appdir/Contents/Info.plist" \
         "$appdir/Contents/PkgInfo" \
         "$out/Applications/$name.app/Contents/"

      mkdir -p "$out/Applications/$name.app/Contents/Resources"
      for icon in "$appdir"/Contents/Resources/*.icns; do
        cp "$icon" "$out/Applications/$name.app/Contents/Resources/"
      done
    done
  fi
'' + ''
  cd ..

  rm -rf $hash
done
'';

    meta = {
      priority = -1;
    };

  };
in
  omnix
