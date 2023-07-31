defmodule Gettext.MergerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Expo.Message
  alias Expo.Messages
  alias Gettext.Merger

  @opts fuzzy: true, fuzzy_threshold: 0.8
  @gettext_config []
  @autogenerated_flags [["elixir-format"]]

  describe "merge/5" do
    test "headers from the old file are kept" do
      old_po = %Messages{
        headers: [~S(Language: it\n), ~S(My-Header: my-value\n)],
        messages: []
      }

      new_pot = %Messages{headers: ["foo"], messages: []}

      assert {new_po, _stats} = Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)
      assert new_po.headers == old_po.headers
    end

    test "obsolete messages are discarded (even the manually entered ones)" do
      old_po = %Messages{
        messages: [
          %Message.Singular{msgid: "obs_auto", msgstr: "foo", flags: @autogenerated_flags},
          %Message.Singular{msgid: "obs_manual", msgstr: "foo"},
          %Message.Singular{msgid: "tomerge", msgstr: "foo"}
        ]
      }

      new_pot = %Messages{messages: [%Message.Singular{msgid: "tomerge", msgstr: ""}]}

      assert {%Messages{messages: [message]}, stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message.msgid == "tomerge"
      assert message.msgstr == "foo"

      assert stats == %{
               exact_matches: 1,
               fuzzy_matches: 0,
               new: 0,
               removed: 2,
               marked_as_obsolete: 0
             }
    end

    test "obsolete messages are marked as obsolete" do
      old_po = %Messages{
        messages: [
          %Message.Singular{msgid: "obs_auto", msgstr: "foo", flags: @autogenerated_flags},
          %Message.Singular{msgid: "obs_manual", msgstr: "foo"},
          %Message.Singular{msgid: "tomerge", msgstr: "foo", obsolete: true}
        ]
      }

      new_pot = %Messages{messages: [%Message.Singular{msgid: "tomerge", msgstr: ""}]}

      assert {%Messages{
                messages: [
                  %Message.Singular{msgid: "tomerge", obsolete: false},
                  %Message.Singular{msgid: "obs_auto", obsolete: true},
                  %Message.Singular{msgid: "obs_manual", obsolete: true}
                ]
              },
              stats} =
               Merger.merge(
                 old_po,
                 new_pot,
                 "en",
                 @opts ++ [on_obsolete: :mark_as_obsolete],
                 @gettext_config
               )

      assert stats == %{
               exact_matches: 1,
               fuzzy_matches: 0,
               new: 0,
               removed: 0,
               marked_as_obsolete: 2
             }
    end

    test "when messages match, the msgstr of the old one is preserved" do
      old_po = %Messages{messages: [%Message.Singular{msgid: "foo", msgstr: "bar"}]}
      new_pot = %Messages{messages: [%Message.Singular{msgid: "foo", msgstr: ""}]}

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message.msgid == "foo"
      assert message.msgstr == "bar"
    end

    test "when messages match, existing translator comments are preserved" do
      # Note that the new message *should* not have any translator comments
      # (comes from a POT file).
      old_po = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", comments: ["# existing comment"]}
        ]
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", comments: ["# new comment"]}
        ]
      }

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message.msgid == "foo"
      assert message.comments == ["# existing comment"]
    end

    test "when messages match, existing translator flags are preserved" do
      old_po = %Messages{
        messages: [%Message.Singular{msgid: "foo", flags: [["fuzzy"]]}]
      }

      new_pot = %Messages{messages: [%Message.Singular{msgid: "foo"}]}

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert Message.has_flag?(message, "fuzzy")
    end

    test "when messages match, existing extracted comments are replaced by new ones" do
      old_po = %Messages{
        messages: [
          %Message.Singular{
            msgid: "foo",
            extracted_comments: ["#. existing comment", "#. other existing comment"]
          }
        ]
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", extracted_comments: ["#. new comment"]}
        ]
      }

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message.extracted_comments == ["#. new comment"]
    end

    test "when messages match, existing references are replaced by new ones" do
      old_po = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", references: [{"foo.ex", 1}]}
        ]
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", references: [{"bar.ex", 1}]}
        ]
      }

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message.references == [{"bar.ex", 1}]
    end

    test "when messages match, existing flags are replaced by new ones" do
      old_po = %Messages{messages: [%Message.Singular{msgid: "foo"}]}

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", flags: @autogenerated_flags}
        ]
      }

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message.flags == @autogenerated_flags
    end

    test "messages with same msgid but different msgctxt are completely different" do
      old_po = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", msgstr: "no context"},
          %Message.Singular{
            msgid: "foo",
            msgctxt: "context",
            msgstr: "with context"
          }
        ]
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "foo", msgctxt: "context", msgstr: ""},
          %Message.Singular{msgid: "foo", msgctxt: "other context", msgstr: ""},
          %Message.Singular{msgid: "foo", msgstr: ""}
        ]
      }

      assert {%Messages{messages: messages}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert [
               %Message.Singular{msgid: "foo", msgctxt: "context", msgstr: "with context"},
               %Message.Singular{msgid: "foo", msgctxt: "other context", msgstr: "no context"} =
                 _fuzzy,
               %Message.Singular{msgid: "foo", msgstr: "no context"}
             ] = messages
    end

    test "new messages are fuzzy-matched against obsolete messages" do
      old_message = %Message.Singular{
        msgid: ["hello world!"],
        msgstr: ["foo"],
        comments: ["# existing comment"],
        extracted_comments: ["#. existing comment"],
        references: [{"foo.ex", 1}]
      }

      old_po = %Messages{messages: [old_message]}

      new_pot = %Messages{
        messages: [
          %Message.Singular{
            msgid: "hello worlds!",
            references: [{"foo.ex", 2}],
            extracted_comments: ["#. new comment"],
            flags: [["my-flag"]]
          }
        ]
      }

      assert {%Messages{messages: [message]}, stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert %{exact_matches: 0, fuzzy_matches: 1, new: 0, removed: 0} = stats

      assert message.msgid == "hello worlds!"
      assert message.msgstr == ["foo"]
      assert message.comments == ["# existing comment"]
      assert message.extracted_comments == ["#. new comment"]
      assert message.references == [{"foo.ex", 2}]
      assert message.flags == [["my-flag", "fuzzy"]]
      assert message.previous_messages == []

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(
                 old_po,
                 new_pot,
                 "en",
                 @opts ++ [store_previous_message_on_fuzzy_match: true],
                 @gettext_config
               )

      assert message.previous_messages == [old_message]
    end

    test "exact matches have precedence over fuzzy matches" do
      old_po = %Messages{
        messages: [
          %Message.Singular{msgid: ["hello world!"], msgstr: ["foo"]},
          %Message.Singular{msgid: ["hello worlds!"], msgstr: ["bar"]}
        ]
      }

      new_pot = %Messages{
        messages: [%Message.Singular{msgid: ["hello world!"]}]
      }

      # Let's check that the "hello worlds!" message is discarded even if it's
      # a fuzzy match for "hello world!".
      assert {%Messages{messages: [message]}, stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      refute Message.has_flag?(message, "fuzzy")
      assert message.msgid == ["hello world!"]
      assert message.msgstr == ["foo"]

      assert %{exact_matches: 1, fuzzy_matches: 0, new: 0, removed: 1} = stats
    end

    test "exact matches do not prevent fuzzy matches for other messages" do
      old_po = %Messages{
        messages: [%Message.Singular{msgid: ["hello world"], msgstr: ["foo"]}]
      }

      # "hello world" will match exactly.
      # "hello world!" should still get a fuzzy match.
      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: ["hello world"]},
          %Message.Singular{msgid: ["hello world!"]}
        ]
      }

      assert {%Messages{messages: [message_1, message_2]}, stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message_1.msgid == ["hello world"]
      assert message_1.msgstr == ["foo"]
      refute Message.has_flag?(message_1, "fuzzy")

      assert message_2.msgid == ["hello world!"]
      assert message_2.msgstr == ["foo"]
      assert Message.has_flag?(message_2, "fuzzy")

      assert stats.new == 0
      assert stats.removed == 0
      assert stats.fuzzy_matches == 1
      assert stats.exact_matches == 1
    end

    test "multiple messages can fuzzy match against a single message" do
      old_po = %Messages{
        messages: [%Message.Singular{msgid: ["hello world"], msgstr: ["foo"]}]
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: ["hello world 1"]},
          %Message.Singular{msgid: ["hello world 2"]}
        ]
      }

      assert {%Messages{messages: [message_1, message_2]}, stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message_1.msgid == ["hello world 1"]
      assert message_1.msgstr == ["foo"]
      assert Message.has_flag?(message_1, "fuzzy")

      assert message_2.msgid == ["hello world 2"]
      assert message_2.msgstr == ["foo"]
      assert Message.has_flag?(message_2, "fuzzy")

      assert %{exact_matches: 0, new: 0, fuzzy_matches: 2, removed: 0} = stats
    end

    test "filling in a fuzzy message preserves references" do
      old_po = %Messages{
        messages: [
          %Message.Singular{
            msgid: ["hello world!"],
            msgstr: ["foo"],
            comments: ["# old comment"],
            references: [{"old_file.txt", 1}]
          }
        ]
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{
            msgid: ["hello worlds!"],
            references: [{"new_file.txt", 2}]
          }
        ]
      }

      assert {%Messages{messages: [message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert Message.has_flag?(message, "fuzzy")
      assert message.msgid == ["hello worlds!"]
      assert message.msgstr == ["foo"]
      assert message.comments == ["# old comment"]
      assert message.references == [{"new_file.txt", 2}]
    end

    test "simple messages can be a fuzzy match for plurals" do
      old_po = %Messages{
        messages: [
          %Message.Singular{
            msgid: ["Here are {count} cocoa balls."],
            msgstr: ["Hier sind {count} Kakaokugeln."],
            comments: ["# Guyanese Cocoballs"],
            references: [{"old_file.txt", 1}]
          }
        ]
      }

      new_pot = %Messages{
        messages: [
          %Message.Plural{
            msgid: ["Here is a cocoa ball."],
            msgid_plural: ["Here are {count} cocoa balls."],
            references: [{"new_file.txt", 2}]
          }
        ]
      }

      assert {%Messages{messages: [message]}, stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert Message.has_flag?(message, "fuzzy")
      assert message.msgid == ["Here is a cocoa ball."]
      assert message.msgid_plural == ["Here are {count} cocoa balls."]
      assert message.msgstr[0] == ["Hier sind {count} Kakaokugeln."]
      assert message.comments == ["# Guyanese Cocoballs"]
      assert message.references == [{"new_file.txt", 2}]

      assert %{exact_matches: 0, fuzzy_matches: 1, new: 0, removed: 0} = stats
    end

    # This has been verified with msgmerge too.
    test "messages fuzzy-match regardless of msgctxt" do
      old_po = %Messages{
        messages: [
          %Message.Singular{msgid: "hello world!", msgctxt: "context", msgstr: ["cfoo"]}
        ]
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{
            msgid: "hello worlds!",
            msgctxt: "completely different"
          },
          %Message.Singular{msgid: "different", msgctxt: "context"}
        ]
      }

      assert {%Messages{messages: [fuzzy_message, new_message]}, stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert %{exact_matches: 0, fuzzy_matches: 1, new: 1, removed: 0} = stats

      assert fuzzy_message.msgid == "hello worlds!"
      assert fuzzy_message.msgstr == ["cfoo"]
      assert fuzzy_message.msgctxt == "completely different"
      assert fuzzy_message.flags == [["fuzzy"]]

      assert new_message.msgid == "different"
      assert new_message.msgctxt == "context"
    end

    test "if there's a Plural-Forms header, it's used to determine number of plural forms" do
      old_po = %Messages{
        headers: [~s(Plural-Forms: nplurals=3;plural=n>1;)],
        messages: []
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "a"},
          %Message.Plural{msgid: "b", msgid_plural: "bs"}
        ]
      }

      assert {%Messages{messages: [message, plural_message]}, _stats} =
               Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

      assert message.msgid == "a"

      assert plural_message.msgid == "b"
      assert plural_message.msgid_plural == "bs"
      assert plural_message.msgstr == %{0 => [""], 1 => [""], 2 => [""]}
    end

    test "if there's a Plural-Forms header with only nplurals=<int>, it's used but deprecated" do
      old_po = %Messages{
        headers: [~s(Plural-Forms: nplurals=3)],
        messages: []
      }

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "a"},
          %Message.Plural{msgid: "b", msgid_plural: "bs"}
        ]
      }

      stderr =
        capture_io(:stderr, fn ->
          assert {%Messages{messages: [message, plural_message]}, _stats} =
                   Merger.merge(old_po, new_pot, "en", @opts, @gettext_config)

          assert message.msgid == "a"

          assert plural_message.msgid == "b"
          assert plural_message.msgid_plural == "bs"
          assert plural_message.msgstr == %{0 => [""], 1 => [""], 2 => [""]}
        end)

      assert stderr =~ ~s(Plural-Forms headers in the form "nplurals=<int>")
    end

    # TODO: remove in v0.24.0
    test "plural forms can be specified as an option, but is deprecated" do
      old_po = %Messages{messages: []}

      new_pot = %Messages{
        messages: [
          %Message.Singular{msgid: "a"},
          %Message.Plural{msgid: "b", msgid_plural: "bs"}
        ]
      }

      opts = [plural_forms: 1] ++ @opts

      stderr =
        capture_io(:stderr, fn ->
          assert {%Messages{messages: [message, plural_message]}, _stats} =
                   Merger.merge(old_po, new_pot, "en", opts, @gettext_config)

          assert message.msgid == "a"

          assert plural_message.msgid == "b"
          assert plural_message.msgid_plural == "bs"
          assert plural_message.msgstr == %{0 => [""]}
        end)

      assert stderr =~ "warning"
      assert stderr =~ "The --plural-forms and :plural_forms options are deprecated"
    end

    test "custom flags defined by :custom_flag_to_keep config are kept" do
      old_po = %Messages{
        messages: [
          %Message.Singular{
            msgid: "a",
            flags: [["elixir-format", "fuzzy", "custom-flag", "other-custom-flag"]]
          }
        ]
      }

      new_po = %Messages{
        messages: [
          %Message.Singular{
            msgid: "a",
            flags: [["elixir-format"]]
          }
        ]
      }

      gettext_config = [custom_flags_to_keep: ["custom-flag"]]

      {merged_message, _stats} = Merger.merge(old_po, new_po, "en", @opts, gettext_config)

      assert %Messages{
               messages: [
                 %Message.Singular{flags: [["elixir-format", "fuzzy", "custom-flag"]]}
               ]
             } = merged_message
    end
  end

  describe "prune_references/2" do
    test "prunes all references when `write_reference_comments` is `false`" do
      po = %Messages{
        messages: [
          %Message.Singular{msgid: "a", references: [[{"path/to/file.ex", 12}]]},
          %Message.Plural{msgid: "a", msgid_plural: "ab", references: [[{"path/to/file.ex", 12}]]}
        ]
      }

      config = [write_reference_comments: false]

      assert %Messages{
               messages: [
                 %Message.Singular{references: []},
                 %Message.Plural{references: []}
               ]
             } = Merger.prune_references(po, config)
    end

    test "prunes reference line numbers when `write_reference_line_numbers` is `false`" do
      po = %Messages{
        messages: [
          %Message.Singular{
            msgid: "a",
            references: [
              [{"path/to/file.ex", 12}, {"path/to/file.ex", 24}, {"a", 1}],
              [{"path/to/file.ex", 42}, {"b", 1}],
              [{"path/to/file.ex", 42}],
              [{"path/to/other_file.ex", 24}]
            ]
          },
          %Message.Plural{msgid: "a", msgid_plural: "ab", references: [[{"path/to/file.ex", 12}]]}
        ]
      }

      config = [write_reference_line_numbers: false]

      assert %Messages{
               messages: [
                 %Message.Singular{
                   references: [
                     ["path/to/file.ex", "a"],
                     ["b"],
                     ["path/to/other_file.ex"]
                   ]
                 },
                 %Message.Plural{references: [["path/to/file.ex"]]}
               ]
             } = Merger.prune_references(po, config)
    end

    test "does nothing per default" do
      po = %Messages{
        messages: [
          %Message.Singular{msgid: "a", references: [[{"path/to/file.ex", 12}]]},
          %Message.Plural{msgid: "a", msgid_plural: "ab", references: [{"path/to/file.ex", 12}]}
        ]
      }

      config = []

      assert po == Merger.prune_references(po, config)
    end
  end

  @tag :tmp_dir
  test "new_po_file/2", %{tmp_dir: tmp_dir} do
    pot_path = Path.join(tmp_dir, "new_po_file.pot")
    new_po_path = Path.join(tmp_dir, "it/LC_MESSAGES/new_po_file.po")

    write_file(pot_path, """
    ## Stripme!
    # A comment
    msgid "foo"
    msgstr "bar"

    msgid "plural"
    msgid_plural "plurals"
    msgstr[0] ""
    msgstr[1] ""

    msgctxt "my_context"
    msgid "with context"
    msgstr ""
    """)

    {new_po, _stats} = Merger.new_po_file(new_po_path, pot_path, "it", [plural_forms: 1] ++ @opts)

    assert new_po.file == new_po_path
    assert new_po.headers == ["", "Language: it\n", "Plural-Forms: nplurals=1\n"]

    assert ["# \"msgid\"s in this file come from POT (.pot) files.", "##" | _] =
             new_po.top_comments

    assert [
             %Message.Singular{} = message,
             %Message.Plural{} = plural_message,
             %Message.Singular{} = context_message
           ] = new_po.messages

    assert message.comments == [" A comment"]
    assert message.msgid == ["foo"]
    assert message.msgstr == ["bar"]

    assert plural_message.msgid == ["plural"]
    assert plural_message.msgid_plural == ["plurals"]
    assert plural_message.msgstr == %{0 => [""]}

    assert context_message.msgctxt == ["my_context"]
    assert context_message.msgid == ["with context"]
  end

  defp write_file(path, contents) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, contents)
  end
end
