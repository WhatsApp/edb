{application, dummy_app_1,
 [{description, "dummy app, does nothing"},
  {id, "dummy_app_1"},
  {vsn, "1.0"},
  {modules, [dummy_app, dummy_app_sup, dummy_app_app]},
  {registered, [dummy_app_1]},
  {applications, [kernel, stdlib]},
  {mod, {dummy_app_app, [dummy_app_1]}}
  ]}.
