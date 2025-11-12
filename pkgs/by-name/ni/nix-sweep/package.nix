{
  lib,
  fetchFromGitHub,
  rustPlatform,
  makeWrapper,
  installShellFiles,
  nix,
  ...
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nix-sweep";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "jzbor";
    repo = "nix-sweep";
    tag = finalAttrs.version;
    hash = "sha256-C83AtqexEzx+8cNZXZyYUtg4gAUyam00IM0eXO8xOgA=";
  };

  cargoHash = "sha256-etqSdtoiSPMQLuMgBK/nnJM8dDTdmRk+MT++zu/9IjM=";

  postInstall = ''
    echo "Generating man pages"
    mkdir ./manpages
    $out/bin/nix-sweep man ./manpages
    installManPage ./manpages/*

    echo "Generating shell completions"
    mkdir ./completions
    $out/bin/nix-sweep completions ./completions
    installShellCompletion completions/nix-sweep.{bash,fish,zsh}
  '';

  postFixup = ''
    wrapProgram $out/bin/nix-sweep \
      --set PATH ${lib.makeBinPath [ nix ]}

    ln -s $out/bin/nix-sweep $out/bin/lix-sweep
  '';

  meta = {
    description = "Utility to clean up old Nix profile generations and left-over garbage collection roots";
    homepage = "https://github.com/jzbor/nix-sweep";
    license = lib.licenses.mit;
    maintainers = [ "gignsky" ];
  };

  nativeBuildInputs = [
    makeWrapper
    installShellFiles
  ];

  buildInputs = [ nix ];
})
