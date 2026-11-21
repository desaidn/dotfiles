// Temporary integration regression: the real personal mod, real native key
// propagation, real QuickJS host queue, and real terminal view on hc::offline().
// Each case gets a fresh process/app home. GPUI's test platform opens no display.
#[test]
fn personal_keyboard_lifecycle() {
    use sha2::Digest;
    let app_dir = std::path::PathBuf::from(std::env::var_os("HERDR_GUIDE_APP_DIR").expect("runner supplies HERDR_GUIDE_APP_DIR"));
    let guide_path = std::env::var_os("HERDR_GUIDE_SOURCE").map(std::path::PathBuf::from).unwrap_or_else(|| app_dir.join("mods/keyboard-guide/main.js"));
    let guide = std::fs::read(&guide_path).unwrap();
    let snapshot = crate::test_tmp().join(format!("personal-guide-{}.js", std::process::id()));
    std::fs::write(&snapshot, &guide).unwrap();
    println!("Guide SHA256: {:x}", sha2::Sha256::digest(&guide));
    let cases = [
        "root_escape", "navigate_escape", "help_escape", "agents_escape",
        "commands_escape", "places_escape", "copy_escape", "copy_move_escape",
        "copy_select_escape", "copy_extend_escape", "copy_yank_reopen",
        "copy_burst_yank_reopen", "copy_click_escape", "root_control_bracket",
        "copy_control_bracket", "copy_backspace", "copy_native_close",
        "copy_external_command", "copy_geometry_zoom",
    ];
    let selected = std::env::var("HERDR_NATIVE_CASE").ok();
    assert!(selected.as_deref().is_none_or(|name| cases.contains(&name)), "unknown native lifecycle case: {selected:?}");
    let mut failures = Vec::new();
    for name in cases.into_iter().filter(|name| selected.as_deref().is_none_or(|s| s == *name)) {
        let home = crate::test_tmp().join(format!("herdr-personal-keys-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&home).unwrap();
        let out = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "window::tests::personal_keyboard_events", "--nocapture", "--test-threads=1"])
            .env("HERDR_APP_HOME", &home)
            .env("HERDR_TEST_WINDOW", "personal_keyboard_events")
            .env("HERDR_NATIVE_CASE", name)
            .env("HERDR_GUIDE_SOURCE", &snapshot)
            .output().unwrap();
        let log = format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
        if out.status.success() && log.contains("1 passed") {
            println!("PASS {name}");
        } else {
            println!("FAIL {name}\n{log}");
            failures.push(name);
        }
        // Only this case's isolated temporary home is removed.
        let _ = std::fs::remove_dir_all(home);
    }
    let _ = std::fs::remove_file(snapshot);
    assert!(failures.is_empty(), "native lifecycle failures: {failures:?}");
}

fn personal_settle(cx: &mut gpui::VisualTestContext) {
    for _ in 0..4 {
        cx.run_until_parked();
        cx.update(|window, cx| {
            window.simulate_next_frame(cx);
            window.draw(cx).clear(cx);
        });
    }
    cx.run_until_parked();
}

fn personal_keys(cx: &mut gpui::VisualTestContext, keys: &str) {
    for key in keys.split(' ') {
        cx.simulate_keystrokes(key);
        personal_settle(cx);
    }
}

fn personal_overlay(view: &gpui::Entity<super::AppWindow>, cx: &mut gpui::VisualTestContext, expected: &str) {
    view.update(cx, |this, _| {
        let errors: Vec<_> = this.copies.values().filter_map(|c| c.error.as_ref()).collect();
        assert!(errors.is_empty(), "native mod errors: {errors:?}");
        let guide: Vec<_> = this.overlays.iter().filter(|o| this.copies.get(&o.slot).is_some_and(|c| c.inst.name == "keyboard-guide")).collect();
        let names: Vec<_> = guide.iter().map(|o| (o.id.as_str(), o.key.as_deref())).collect();
        match expected {
            "closed" => assert!(guide.is_empty(), "guide must close; found {names:?}"),
            "copy" => {
                assert_eq!(guide.len(), 1, "one copy strip, found {names:?}");
                let copy = this.copies.get(&guide[0].slot).unwrap();
                assert_eq!(copy.inst.props.get("mode").and_then(|m| m.as_str()), Some("copy"));
            }
            _ => {
                assert_eq!(guide.len(), 1, "one guide, found {names:?}");
                assert_eq!(guide[0].id, "mod-keyboard-guide");
            }
        }
    });
    if expected == "copy" { personal_copy_geometry(view, cx); }
}

fn personal_copy_geometry(view: &gpui::Entity<super::AppWindow>, cx: &mut gpui::VisualTestContext) {
    let width = view.update(cx, |this, _| {
        let overlay = this.overlays.iter().find(|o| this.copies.get(&o.slot).is_some_and(|c| c.inst.props.get("mode").and_then(|v| v.as_str()) == Some("copy"))).unwrap();
        assert!(overlay.kind == super::OverlayKind::Popup, "copy must retain native popup dismissal without dialog dimming");
        overlay.size.width * crate::settings::zoom()
    });
    cx.update(|window, _| {
        let scale = window.scale_factor();
        let viewport = window.viewport_size();
        // Read the actual painted native frame, not the requested coordinates.
        // The guide's inner background has no rounded border; terminal panes
        // do not have this frame's width and rounded corners.
        let quads = window.painted_quads();
        let mut frames: Vec<_> = quads.iter().filter(|q|
            (q.bounds.size.width.0 / scale - width).abs() <= 1.0
            && q.border_widths.top.0 > 0.0
            && q.corner_radii.top_left.0 > 0.0
        ).map(|q| q.bounds).collect();
        // GPUI splits a transparent frame into four border strips, all with
        // the same outer bounds and separate clipping masks.
        frames.dedup();
        assert_eq!(frames.len(), 1, "copy must paint one visible native popup frame; found {frames:?}");
        let frame = frames[0];
        let content: Vec<_> = quads.iter().filter(|q|
            !q.background.is_transparent()
            && q.bounds.left() >= frame.left() && q.bounds.right() <= frame.right()
            && q.bounds.top() >= frame.top() && q.bounds.bottom() <= frame.bottom()
        ).map(|q| q.bounds.intersect(&q.content_mask.bounds)).filter(|visible|
            visible.size.width.0 / scale > 500.0 && visible.size.height.0 / scale > 80.0
        ).collect();
        assert!(!content.is_empty(), "copy popup must paint substantial opaque visible content, frame={frame:?}");
        let center_x = (frame.origin.x.0 + frame.size.width.0 / 2.0) / scale;
        let center_y = (frame.origin.y.0 + frame.size.height.0 / 2.0) / scale;
        assert!((center_x - f32::from(viewport.width) / 2.0).abs() <= 2.0
            && (center_y - f32::from(viewport.height) / 2.0).abs() <= 2.0,
            "painted copy popup must be centered: frame={frame:?}, viewport={viewport:?}, scale={scale}");
    });
}

fn personal_restored(view: &gpui::Entity<super::AppWindow>, cx: &mut gpui::VisualTestContext) {
    personal_overlay(view, cx, "closed");
    cx.update(|window, cx| view.update(cx, |this, cx| {
        assert!(this.pane_term("pa").unwrap().focus.is_focused(window), "terminal must regain keyboard focus");
        assert!(this.model.tab("a").is_some(), "Escape must not close the original tab");
        assert!(this.pane_term("pa").unwrap().view.read(cx).selection().is_none(), "closing must clear the terminal selection");
    }));
    let before = crate::terminal::personal_fixture_key_count();
    personal_keys(cx, "r");
    assert_eq!(crate::terminal::personal_fixture_key_count(), before + 1, "the terminal's real key handler must receive the next ordinary key");
    personal_overlay(view, cx, "closed");
}

#[gpui::test]
fn personal_keyboard_events(cx: &mut gpui::TestAppContext) {
    use serde_json::json;
    if !running_alone("personal_keyboard_events") { return; }
    let scenario = std::env::var("HERDR_NATIVE_CASE").unwrap();
    let repo = std::path::PathBuf::from(std::env::var_os("HERDR_GUIDE_APP_DIR").unwrap());
    let source_path = std::env::var("HERDR_GUIDE_SOURCE").unwrap_or_else(|_| repo.join("mods/keyboard-guide/main.js").to_string_lossy().into_owned());
    let source = std::fs::read_to_string(&source_path).unwrap();
    cx.update(gpui_base::init);
    let (view, cx) = open_window(cx, "keyboard-guide", &source, json!({
        "id": "main", "type": "block", "content": {"tab": "active"}
    }));
    let home = crate::mods::app_dir();
    std::fs::copy(repo.join("mods/keyboard-guide/mod.json"), home.join("mods/keyboard-guide/mod.json")).unwrap();
    std::fs::copy(repo.join("keys.json"), home.join("keys.json")).unwrap();
    cx.update(|window, cx| view.update(cx, |this, cx| {
        this.reload_config(window, cx);
        this.model.add_space("s1", "one", home.to_string_lossy().as_ref(), crate::model::Tab::new("a", "a", "pa", "t1"));
        this.model.select_tab("a");
        this.live.insert("t1".into(), json!({"address":"t1", "state":"live", "pid":1}));
        crate::mods::publish_terminals(json!([{"address":"t1", "state":"live", "pid":1}]));
        this.sync(window, cx);
        this.pane_term("pa").unwrap().view.update(cx, |terminal, cx| terminal.personal_fixture_output(cx));
    }));
    cx.simulate_resize(gpui::size(gpui::px(1200.), gpui::px(800.)));
    if scenario == "copy_geometry_zoom" {
        cx.update(|window, cx| view.update(cx, |this, cx| this.write_person(|person| person.zoom = 1.5, window, cx)));
    }
    personal_settle(cx);

    // Reopen the actual key-bound overlay repeatedly, with the terminal focused.
    for _ in 0..3 {
        cx.update(|_, cx| cx.write_to_clipboard(gpui::ClipboardItem::new_string("untouched-native-sentinel".into())));
        personal_keys(cx, "ctrl-b");
        personal_overlay(&view, cx, "root");
        if scenario.starts_with("copy_") {
            if scenario == "copy_external_command" {
                // Same async nextCommand route as `herdr-app do`, including
                // the reported help-to-copy transition.
                for command in ["keyboard-guide.help", "keyboard-guide.copy"] {
                    cx.update(|window, cx| view.update(cx, |this, cx| {
                        let reply = this.run_as(command, json!({}), false, window, cx);
                        assert_eq!(reply.get("ok"), Some(&json!(true)), "external command {command}: {reply}");
                    }));
                    personal_settle(cx);
                }
            } else { personal_keys(cx, "["); }
            personal_overlay(&view, cx, "copy");
            match scenario.as_str() {
                "copy_move_escape" => personal_keys(cx, "h h"),
                "copy_select_escape" => personal_keys(cx, "h h v"),
                "copy_extend_escape" | "copy_click_escape" | "copy_backspace" | "copy_native_close" => personal_keys(cx, "h h v l"),
                "copy_yank_reopen" => personal_keys(cx, "h h v l y"),
                "copy_burst_yank_reopen" => {
                    cx.simulate_keystrokes("h h v l y");
                    personal_settle(cx);
                }
                _ => {}
            }
            if scenario.contains("yank") {
                personal_restored(&view, cx);
                cx.update(|_, cx| {
                    let copied = cx.read_from_clipboard().and_then(|item| item.text()).unwrap_or_default();
                    assert!(!copied.is_empty() && copied != "untouched-native-sentinel", "y must copy real terminal text; got {copied:?}");
                    assert!("copy this useful text".contains(&copied), "copied text must come from the populated terminal, got {copied:?}");
                });
                continue;
            }
            if matches!(scenario.as_str(), "copy_select_escape" | "copy_extend_escape" | "copy_click_escape" | "copy_backspace" | "copy_native_close") {
                view.update(cx, |this, cx| {
                    assert!(this.pane_term("pa").unwrap().view.read(cx).selection().is_some(), "v must create a real native terminal selection");
                });
            }
            if scenario == "copy_backspace" {
                personal_keys(cx, "backspace");
                personal_overlay(&view, cx, "root");
                view.update(cx, |this, cx| assert!(this.pane_term("pa").unwrap().view.read(cx).selection().is_none()));
            }
            if scenario == "copy_native_close" {
                // Native outside-click and overlay controls remove the copy
                // without calling its key handler: its close hook must clean up.
                cx.update(|window, cx| view.update(cx, |this, cx| {
                    let id = this.overlays.iter().find(|o| this.copies.get(&o.slot).is_some_and(|c| c.inst.name == "keyboard-guide")).unwrap().id.clone();
                    this.close_overlay(&id, window, cx);
                }));
                personal_settle(cx);
                personal_restored(&view, cx);
                continue;
            }
            if scenario == "copy_click_escape" {
                cx.simulate_click(gpui::point(gpui::px(30.), gpui::px(700.)), Default::default());
                personal_settle(cx);
                cx.update(|window, cx| view.update(cx, |this, _| {
                    assert!(this.pane_term("pa").unwrap().focus.is_focused(window), "click must move focus from copy strip to terminal");
                }));
            }
        } else {
            match scenario.as_str() {
                "navigate_escape" => personal_keys(cx, "g"),
                "help_escape" => personal_keys(cx, ": h e l p enter"),
                "agents_escape" => personal_keys(cx, "a"),
                "commands_escape" => personal_keys(cx, ": a p p"),
                "places_escape" => personal_keys(cx, "w o n e"),
                _ => {}
            }
        }
        personal_keys(cx, if scenario.ends_with("control_bracket") { "ctrl-[" } else { "escape" });
        personal_restored(&view, cx);
    }
}
