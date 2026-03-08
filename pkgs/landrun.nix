{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "landrun";
  version = "0.1.14";

  src = fetchFromGitHub {
    owner = "Zouuup";
    repo = "landrun";
    rev = "v${version}";
    hash = "sha256-6TWcsJpebfLnUTYflP2j0/Tuv4PdFx/sMATc4Km1AIE=";
  };

  vendorHash = "sha256-Bs5b5w0mQj1MyT2ctJ7V38Dy60moB36+T8TFH38FA08=";

  subPackages = [ "cmd/landrun" ];

  meta = with lib; {
    description = "Landlock sandboxing CLI for Linux";
    homepage = "https://github.com/Zouuup/landrun";
    changelog = "https://github.com/Zouuup/landrun/releases/tag/v${version}";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "landrun";
  };
}
