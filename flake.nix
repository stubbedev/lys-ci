{
  description = "lys-ci - the CI tool every lys repository shares";

  outputs = {self}: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    app = {
      type = "app";
      program = "${self}/vendor-hash";
    };
  in {
    apps = builtins.listToAttrs (map (system: {
        name = system;
        value = {
          vendor-hash = app;
          default = app;
        };
      })
      systems);
  };
}
