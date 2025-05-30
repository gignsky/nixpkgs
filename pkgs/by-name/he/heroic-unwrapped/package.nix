{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  pnpm_9,
  nodejs,
  python3,
  makeWrapper,
  # Upstream uses EOL Electron 31.  Use next oldest version.
  electron_34,
  vulkan-helper,
  gogdl,
  legendary-heroic,
  nile,
  comet-gog,
}:

let
  electron = electron_34;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "heroic-unwrapped";
  version = "2.16.1";

  src = fetchFromGitHub {
    owner = "Heroic-Games-Launcher";
    repo = "HeroicGamesLauncher";
    rev = "v${finalAttrs.version}";
    hash = "sha256-BnBzbbyi9cdO6W59cnY13hnhH+tjrTryTp9XIcERwh4=";
  };

  pnpmDeps = pnpm_9.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-2IQyXULgFoz0rFQ8SwERgMDzzo7pZ3DbqhwrWNYSwRo=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_9.configHook
    python3
    makeWrapper
  ];

  patches = [
    # Make Heroic create Steam shortcuts (to non-steam games) with the correct path to heroic.
    ./fix-non-steam-shortcuts.patch
  ];

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  buildPhase = ''
    runHook preBuild

    # set nodedir to prevent node-gyp from downloading headers
    export npm_config_nodedir=${electron.headers}

    pnpm --offline electron-vite build
    pnpm --offline electron-builder \
      --linux \
      --dir \
      -c.asarUnpack="**/*.node" \
      -c.electronDist=${electron.dist} \
      -c.electronVersion=${electron.version}

    runHook postBuild
  '';

  # --disable-gpu-compositing is to work around upstream bug
  # https://github.com/electron/electron/issues/32317
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/opt/heroic"
    cp -r dist/linux-unpacked/resources "$out/opt/heroic"

    cp -r public "$out/opt/heroic/resources/app.asar.unpacked/build"
    rm -rf "$out/opt/heroic/resources/app.asar.unpacked/build/bin"
    mkdir -p "$out/opt/heroic/resources/app.asar.unpacked/build/bin/x64/linux"
    ln -s \
      "${lib.getExe gogdl}" \
      "${lib.getExe legendary-heroic}" \
      "${lib.getExe nile}" \
      "${lib.getExe comet-gog}" \
      "${lib.getExe vulkan-helper}" \
      "$out/opt/heroic/resources/app.asar.unpacked/build/bin/x64/linux"

    makeWrapper "${electron}/bin/electron" "$out/bin/heroic" \
      --inherit-argv0 \
      --set ELECTRON_FORCE_IS_PACKAGED 1 \
      --add-flags --disable-gpu-compositing \
      --add-flags $out/opt/heroic/resources/app.asar \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    install -D "flatpak/com.heroicgameslauncher.hgl.desktop" "$out/share/applications/com.heroicgameslauncher.hgl.desktop"
    install -D "src/frontend/assets/heroic-icon.svg" "$out/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg"
    substituteInPlace "$out/share/applications/com.heroicgameslauncher.hgl.desktop" \
      --replace-fail "Exec=heroic-run --ozone-platform-hint=auto" "Exec=heroic"

    runHook postInstall
  '';

  passthru = {
    inherit (finalAttrs) pnpmDeps;
    updateScript = nix-update-script { };
  };

  meta = with lib; {
    description = "Native GOG, Epic, and Amazon Games Launcher for Linux, Windows and Mac";
    homepage = "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher";
    changelog = "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ aidalgol ];
    # Heroic may work on nix-darwin, but it needs a dedicated maintainer for the platform.
    # It may also work on other Linux targets, but all the game stores only
    # support x86 Linux, so it would require extra hacking to run games via QEMU
    # user emulation.  Upstream provide Linux builds only for x86_64.
    platforms = [ "x86_64-linux" ];
    mainProgram = "heroic";
  };
})
