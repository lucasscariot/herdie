use herdie_core::{ConnectionProfile, CoreError, HostTrust, HostTrustDecision};

fn valid_profile() -> ConnectionProfile {
    ConnectionProfile::new(
        "studio".into(),
        "Mac Studio".into(),
        "studio.tailnet.ts.net".into(),
        22,
        "lucas".into(),
    )
    .expect("valid profile")
}

#[test]
fn trims_and_accepts_a_complete_profile() {
    let profile = ConnectionProfile::new(
        "  studio  ".into(),
        "  Mac Studio  ".into(),
        "  studio.tailnet.ts.net  ".into(),
        22,
        "  lucas  ".into(),
    )
    .expect("valid profile");

    assert_eq!(profile.id, "studio");
    assert_eq!(profile.name, "Mac Studio");
    assert_eq!(profile.host, "studio.tailnet.ts.net");
    assert_eq!(profile.username, "lucas");
}

#[test]
fn rejects_each_missing_connection_field() {
    let cases = [
        ("", "Mac Studio", "host", 22, "lucas", "id"),
        ("studio", "", "host", 22, "lucas", "name"),
        ("studio", "Mac Studio", "", 22, "lucas", "host"),
        ("studio", "Mac Studio", "host", 0, "lucas", "port"),
        ("studio", "Mac Studio", "host", 22, "", "username"),
    ];

    for (id, name, host, port, username, field) in cases {
        let error =
            ConnectionProfile::new(id.into(), name.into(), host.into(), port, username.into())
                .expect_err("profile should be rejected");

        assert_eq!(
            error,
            CoreError::InvalidProfile {
                field: field.into()
            }
        );
    }
}

#[test]
fn host_trust_requires_first_use_approval() {
    let decision = HostTrust::verify(None, "SHA256:presented");

    assert_eq!(
        decision,
        HostTrustDecision::Unknown {
            presented: "SHA256:presented".into()
        }
    );
}

#[test]
fn host_trust_accepts_only_an_exact_known_fingerprint() {
    assert_eq!(
        HostTrust::verify(Some("SHA256:known"), "SHA256:known"),
        HostTrustDecision::Trusted
    );
    assert_eq!(
        HostTrust::verify(Some("SHA256:known"), "SHA256:changed"),
        HostTrustDecision::Mismatch {
            expected: "SHA256:known".into(),
            presented: "SHA256:changed".into()
        }
    );
}

#[test]
fn profile_never_contains_credentials() {
    let json = serde_json::to_string(&valid_profile()).expect("serialize profile");

    assert!(!json.contains("password"));
    assert!(!json.contains("private_key"));
}
