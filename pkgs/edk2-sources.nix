# EDK2 at the commits the Pi Firmware Task Force builds its releases from (github.com/pftf/RPi3 v1.53.1 and
# github.com/pftf/RPi4 v1.53 pin the same three).
{fetchFromGitHub}: {
  version = "1.53.1";

  edk2 = fetchFromGitHub {
    owner = "tianocore";
    repo = "edk2";
    rev = "2970e5699ba6267f3384ffab20f96647578aebc8";
    fetchSubmodules = true;
    hash = "sha256-LRq5SGAcqMl9PlSaV/Q2qE1HLMXHghozwgZP4A3FCts=";
  };

  edk2-platforms = fetchFromGitHub {
    owner = "tianocore";
    repo = "edk2-platforms";
    rev = "c8295e076affae5cf04fd4234db13a0e025f44e1";
    hash = "sha256-weLST5yYwpkFnbagaQfv514eYTXUDE6p5yRLBNSrzbc=";
  };

  edk2-non-osi = fetchFromGitHub {
    owner = "tianocore";
    repo = "edk2-non-osi";
    rev = "7ac12d81e02b323bffdf1ef3c188ea33c2185c91";
    hash = "sha256-lX+2Ayul8o4fyM2THN0s6kNqSojRAqUtn8fxU/GeY+o=";
  };
}
