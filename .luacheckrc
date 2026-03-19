std = "luajit"
globals = { "kong", "ngx" }

files["spec/**/*.lua"] = {
  std = "+busted",
}
