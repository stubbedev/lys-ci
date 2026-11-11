{
  description = "lys-ci - the CI tools every lys repository shares";

  outputs = {self}: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    tool = name: {
      type = "app";
      program = "${self}/${name}";
    };
    vendor-hash = tool "vendor-hash";
  in {
    apps = builtins.listToAttrs (map (system: {
        name = system;
        value = {
          inherit vendor-hash;
          no-fused = tool "bin/no-fused";
          bump-lys = tool "bin/bump-lys";
          release = tool "bin/release";
          train = tool "bin/train";
          default = vendor-hash;
        };
      })
      systems);
  };
}
