{application, dummy_app_2,
 [{description, "dummy app, does nothing"},
  {id, "dummy_app_2"},
  {vsn, "1.0"},
  {modules, [dummy_app, dummy_app_sup, dummy_app_app]},
  {registered, [dummy_app_2]},
  {applications, [kernel, stdlib]},
  {mod, {dummy_app_app, [dummy_app_2]}}
  ]}.