{ lib
, stdenv
, fetchFromGitHub
, nodejs_22
, pnpm_10
, pkg-config
, python3
, makeWrapper
, vips
, zstd
, sourceInfo
, gatewaySrc ? null
, pnpmDepsHash ? null
}:

assert gatewaySrc == null || pnpmDepsHash != null;

let
  pnpmPlatform = if stdenv.hostPlatform.isDarwin then "darwin" else "linux";
  pnpmArch = if stdenv.hostPlatform.isAarch64 then "arm64" else "x64";
in

stdenv.mkDerivation (finalAttrs: {
  pname = "clawdbot-gateway";
  version = "2.0.0-beta4";

  src = if gatewaySrc != null then gatewaySrc else fetchFromGitHub sourceInfo;

  pnpmDeps = pnpm_10.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = if pnpmDepsHash != null
      then pnpmDepsHash
      else "sha256-TITqhJhk5cHqCDmeX+KJ1hqt9dEbvJu6vi8xhteYfC4=";
    fetcherVersion = 2;
  };

  nativeBuildInputs = [
    nodejs_22
    pnpm_10
    pkg-config
    python3
    makeWrapper
    zstd
  ];

  buildInputs = [ vips ];

  env = {
    SHARP_FORCE_GLOBAL_LIBVIPS = "1";
    npm_config_build_from_source = "true";
    npm_config_arch = pnpmArch;
    npm_config_platform = pnpmPlatform;
    PNPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS = "false";
  };

  preBuild = ''
    export HOME=$(mktemp -d)
    export STORE_PATH=$(mktemp -d)

    fetcherVersion=$(cat "${finalAttrs.pnpmDeps}/.fetcher-version" || echo 1)
    if [ "$fetcherVersion" -ge 3 ]; then
      tar --zstd -xf "${finalAttrs.pnpmDeps}/pnpm-store.tar.zst" -C "$STORE_PATH"
    else
      cp -Tr "${finalAttrs.pnpmDeps}" "$STORE_PATH"
    fi

    chmod -R +w "$STORE_PATH"

    pnpm config set store-dir "$STORE_PATH"
    pnpm config set package-import-method clone-or-copy
    pnpm config set manage-package-manager-versions false
  '';

  buildPhase = ''
    runHook preBuild
    pnpm install --offline --frozen-lockfile
    patchShebangs node_modules/{*,.*}
    pnpm build
    pnpm ui:build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/clawdbot $out/bin

    cp -r dist node_modules package.json ui $out/lib/clawdbot/

    makeWrapper ${nodejs_22}/bin/node $out/bin/clawdbot \
      --add-flags "$out/lib/clawdbot/dist/index.js" \
      --set-default CLAWDBOT_NIX_MODE "1"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Telegram-first AI gateway (Clawdbot)";
    homepage = "https://github.com/clawdbot/clawdbot";
    license = licenses.mit;
    platforms = platforms.darwin ++ platforms.linux;
    mainProgram = "clawdbot";
  };
})
