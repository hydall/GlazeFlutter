import json
import os
import shutil
import sqlite3
import time

DB = os.path.join(os.environ['APPDATA'], 'Glaze', 'glaze.db')
BACKUP = f"{DB}.before_studio_normalized_v1_{int(time.time())}.bak"
NEW_ID = 'studio_normalized_v1'
NEW_NAME = 'Studio Normalized v1'

shutil.copy2(DB, BACKUP)
conn = sqlite3.connect(DB)
try:
    row = conn.execute(
        "SELECT blocks_json FROM studio_preset_rows WHERE preset_id='default'"
    ).fetchone()
    if row is None:
        raise RuntimeError('default Studio preset not found')
    original_json = row[0]
    blocks = json.loads(original_json)
    by_id = {block['id']: block for block in blocks}

    # Remove only confirmed legacy duplicates. Disabled style/genre alternatives
    # remain available for deliberate switching.
    remove_ids = {
        'continuity_task_orig',
        'narrative_task_orig',
        'block_1783457259932',  # disabled pregen duplicate of final anti-drama
    }
    blocks = [block for block in blocks if block['id'] not in remove_ids]
    by_id = {block['id']: block for block in blocks}

    by_id['pregen_narrative_engine']['enabled'] = False

    by_id['continuity_task_universal']['content'] += '''

EVIDENCE BOUNDARY:
- Report as established only facts explicitly supported by the card, supplied lore, memory, ledger, or visible chat.
- Do not infer hidden emotion, symbolism, motives, off-screen activity, or events during a time skip.
- A plausible interpretation is not a continuity fact. Put uncertainty in an explicit "Possible" item or omit it.
- Source-material knowledge may fill gaps for the final writer. Your silence does not make a known canon person or fact unknown.
- Never treat absence from the character card as evidence that a source-material person, place, or fact is unknown.'''

    by_id['agency_task']['content'] = by_id['agency_task']['content'].replace(
        'Enforce user autonomy and character authenticity. Never write the user\'s dialogue, actions, thoughts, feelings, intentions, or decisions. Characters act only from established knowledge, psychology, history, physical limits, and current pressure. Produce constraints only, not prose.',
        '''Enforce user autonomy and character authenticity. The final writer may render actions the user explicitly declared in the latest turn, but may not invent the user's next action, decision, intent, thought, feeling, or dialogue. Treat declared action as fixed input whose execution and consequences may be shown, not as permission to continue controlling the user. Produce constraints only, not prose.''',
    )
    by_id['agency_task']['content'] += '''

EVIDENCE BOUNDARY:
- Distinguish established psychology from a plausible reaction.
- Do not state that a character feels, recognizes, associates, remembers, or interprets something unless supported by the card, supplied lore, ledger, or visible chat.
- Put plausible reactions under Options, not established Constraints.
- Never invent off-screen emotional development during a time skip.'''

    narrative = by_id['narrative_task_universal']['content']
    marker = 'STAGNATION DETECTION:'
    if marker in narrative:
        narrative = narrative[:narrative.index(marker)] + '''STAGNATION DETECTION:
- If the last 3 beats appear stagnant, report the stagnation risk instead of inventing an event.
- Prefer a development derived from an established motive, pending thread, object, deadline, access constraint, or environmental condition.
- Do not introduce a stranger, job, threat, revelation, message, or faction action solely to create movement.
- If no grounded development exists, recommend a smaller practical or character-driven shift.'''
    by_id['narrative_task_universal']['content'] = narrative

    by_id['world_task']['content'] = '''Guide living-world and NPC activity. NPCs should act only when the scene supports it and should affect the scene without stealing focus. Produce practical world-state guidance only.

NPC PROACTIVITY:
- NPCs and the world may act independently of {{user}}, but actions must derive from an established character motive, duty, pending thread, deadline, location, or active pressure.
- Existing card hooks may be activated proactively when the current scene provides a credible bridge.
- Do not invent strangers, jobs, threats, revelations, messages, or faction actions solely because the scene is quiet.

STAGNATION DETECTION:
- If the last 3 turns repeat the same routine without a concrete shift, output a stagnation flag.
- Name one grounded development from existing state. If none exists, recommend a small practical change rather than a new plot event.
- Slow burn is not stagnation: changed tolerance, access, distance, timing, attention, or boundaries count as movement.'''

    response = by_id['final_response_shape_contract']['content']
    start = response.index('SOURCE-MATERIAL KNOWLEDGE:')
    end = response.index('\n\nDo not infer desired response length', start)
    response = response[:start] + '''SOURCE PRIORITY:
1. Explicit user correction and established current-chat canon.
2. Character card and supplied lore.
3. Ledger, memory, and tracker briefs.
4. Model knowledge of the source material as a non-binding gap filler.

- Source-material knowledge is allowed and useful. Absence from the character card does NOT mean a known canon person, place, or fact is unknown.
- Use relevant source knowledge when it does not contradict higher-priority sources.
- Model familiarity alone must not rewrite relationships, chronology, characterization, or facts already established by the card or chat.
- Tracker silence is not a prohibition, and tracker speculation is not canon.'''+ response[end:]
    response = response.replace(
        '12+ is acceptable only when the scene genuinely needs separate beats.',
        '12 paragraphs is the hard maximum; use fewer when the beat does not need them.',
    )
    by_id['final_response_shape_contract']['content'] = response

    by_id['final_narrative_engine']['content'] = by_id['final_narrative_engine']['content'].replace(
        '- Enforce internal continuity and cause-and-effect. Actions carry persistent consequences; relationships shift based on accumulated behavior, not single moments.',
        '- Enforce internal continuity and cause-and-effect. Actions carry persistent consequences; relationships shift based on accumulated behavior, not single moments.\n- Track physical injury silently after it is established. Mention it again only when it changes a concrete action, capability, risk, or decision in the current beat. Persistence in world state is not permission to repeat pain, vitals, healing telemetry, or medical commentary.',
    )
    by_id['final_narrative_engine']['content'] = by_id['final_narrative_engine']['content'].replace(
        '- Never restate, echo, or summarize what {{user}} said or did. Show the consequences directly. Keep dialogue sharp and purposeful. Avoid extended inner monologues unless the scene demands them.',
        '''- Never repeat, quote, paraphrase, or re-stage {{user}}'s dialogue. It has already been spoken.
- You may render an action explicitly declared by {{user}} once in cinematic prose when its physical execution matters. Add contact, resistance, timing, reactions, and immediate consequences rather than merely restating the input.
- Do not invent the user's next action, movement, decision, intention, thought, feeling, success, or failure beyond what the declared action and established world causally determine. Stop at the next genuine player choice.''',
    )

    by_id['final_user_autonomy']['content'] = '''<user_control>
# Rule: preserve player authorship while rendering declared action

DIALOGUE — ABSOLUTE:
- NEVER repeat, quote, paraphrase, summarize, or re-stage {{user}}'s dialogue. It has already been spoken in the scene.
- NEVER write new dialogue for {{user}}.

DECLARED ACTION — MAY BE RENDERED:
- You MAY describe an action that {{user}} explicitly declared in the latest message, including its physical execution, contact, resistance, sensory mechanics, NPC reactions, environmental response, and immediate consequences.
- Render it once and move through cause and effect. Do not merely translate the user's action into third-person prose or replay the same beat line by line.
- In combat, resolve each declared action far enough to show what it actually does. Success is not guaranteed; established capabilities, opposition, timing, and physics determine the result.

BOUNDARY:
- NEVER invent {{user}}'s next voluntary action, movement, decision, intention, thought, feeling, or emotional reaction.
- NEVER extend a declared action into an undeclared follow-up. Stop at the next genuine player choice.
- External forces may impose sensations, impacts, displacement, restraint, injury, or consequences when causally established; do not convert those into voluntary choices.

The user's input is fixed authorship. The assistant supplies cinematic realization and consequences, not replacement authorship.
</user_control>'''

    guard = by_id['guard_task']['content']
    guard_start = guard.index('## Anti-Echo')
    guard_end = guard.index('\n\nProduce a guard brief only.', guard_start)
    by_id['guard_task']['content'] = guard[:guard_start] + '''## Player-Input Handling
- Never repeat, quote, paraphrase, or re-stage {{user}}'s dialogue; treat it as already spoken.
- A declared user action may be rendered once when execution matters, especially in combat. Require new physical information: mechanics, contact, resistance, reactions, or consequences.
- Flag a bare third-person replay, copied beat order, or 4+ consecutive words from the user's action as echo.
- Never let action rendering add an undeclared follow-up, choice, intent, thought, feeling, or new dialogue.
- Hand control back at the next genuine player decision.'''+ guard[guard_end:]

    cleaner = by_id['cleaner_rules']['content']
    cleaner = cleaner.replace(
        '''- Do not copy, quote, paraphrase, or mirror {{user}}'s last message.
- Do not mirror {{user}}'s sentence structure, beat order, or dialogue rhythm.
- Do not reference "your words", "what you just said", "when you said", "as you asked", or similar meta-echoes.
- Do not reuse any 4+ consecutive words from {{user}}'s latest message, except a single proper noun.''',
        '''- Remove any repeated, quoted, paraphrased, or re-staged {{user}} dialogue; it has already been spoken.
- Preserve cinematic rendering of an explicitly declared user action only when it adds physical execution, contact, resistance, reactions, or immediate consequences.
- Rewrite bare third-person action replay, copied beat order, or any 4+ consecutive words copied from the user's action.
- Remove any undeclared user follow-up, decision, intention, thought, feeling, emotional reaction, or new dialogue.
- Do not reference "your words", "what you just said", "when you said", "as you asked", or similar meta-echoes.''',
    )
    by_id['cleaner_rules']['content'] = cleaner

    anime = by_id['final_prose_style_anime']['content']
    anime = anime.replace(
        '- Every dialogue line should work on two levels: surface meaning + underlying intent (what the character tests, withholds, threatens, probes, or wants). A line that means exactly what it says is flat regardless of length.',
        '- Use layered subtext in social, intimate, guarded, deceptive, or emotionally charged dialogue. Functional, tactical, medical, emergency, and time-critical dialogue may be direct. Do not manufacture a hidden motive for every spoken line.',
    )
    anime = anime.replace(
        '- Every dialogue line carries 2-3 layers of meaning: surface words, unspoken intent, and emotional undertone. A character says one thing, means another, and feels a third. The reader senses all three.',
        '- Social and emotionally charged dialogue may carry layered surface meaning, intent, and undertone. Tactical or time-critical speech may mean exactly what it says.',
    )
    anime = anime.replace(
        '### DIALOGUE SUBTEXT (every spoken line)',
        '### DIALOGUE SUBTEXT (when scene mode supports it)',
    ).replace(
        '- Every dialogue line must work on two levels: surface meaning + underlying intent (test, withhold, threaten, probe, seduce, dismiss, invite).',
        '- In social, guarded, intimate, or deceptive exchanges, dialogue should work on surface and intent levels. Direct operational dialogue is allowed.',
    )
    by_id['final_prose_style_anime']['content'] = anime

    by_id['final_studio_brief_macros']['content'] = by_id['final_studio_brief_macros']['content'].replace(
        '<studio_world_guard_beauty_briefs>', '<studio_world_guard_briefs>'
    ).replace(
        '</studio_world_guard_beauty_briefs>', '</studio_world_guard_briefs>'
    ).replace('\n<beauty>\n{{studio_beauty_brief}}\n</beauty>', '')

    by_id['ledger_system']['content'] += '''

SOURCE PRIORITY AND OVERRIDES:
- Priority: explicit user correction and established session canon; then character card and supplied lore; then current structured state; then model source-material knowledge.
- Source-material knowledge may fill genuine gaps. Absence from the card does not make a known canon person or fact unknown.
- Model knowledge must not contradict higher-priority sources. A source fact becomes session canon after it appears in an accepted user/assistant turn; then persist it with evidence.
- Explicit retcons replace contradictory old state. Delete or overwrite stale keys instead of preserving both versions.
- Scope each retcon to the specific fact, condition, event, and timeline position it identifies. A retcon of an earlier injury does not prohibit a later independently established injury.
- When a later accepted turn establishes a new state in the same category, preserve the old retcon as a separate tombstone/override and write the new current state under its normal key with later evidence. Do not use a broad canon_lock that would block legitimate future updates.

STATE NORMALIZATION:
- Values describe current truth, not a history log. Replace stale scene details rather than appending summaries.
- card_overrides stores only durable deviations from the character-card baseline, never temporary combat events, posture, equipment use, or telemetry.
- relationship_to_user and attitude_to_user store only the current relationship/attitude, not actions, dialogue, injuries, or scene summaries.
- scene.present_entities stores names plus only minimal current presence state.
- world:time stores current in-world time only; timers, distances, and deadlines belong in separate keys.
- Avoid invented exact numbers. Persist precision only when explicitly stated in accepted chat.'''

    # Keep every intentional disabled alternative, but make ordering deterministic.
    for section in ('cleaner', 'ledger', 'build', 'brief_parser', 'pregen', 'final'):
        section_blocks = [b for b in blocks if b.get('section') == section]
        section_blocks.sort(key=lambda b: (b.get('order', 0), blocks.index(b)))
        for order, block in enumerate(section_blocks):
            block['order'] = order

    normalized_json = json.dumps(blocks, ensure_ascii=False, separators=(',', ':'))
    now = int(time.time())
    conn.execute(
        '''INSERT INTO studio_preset_rows(preset_id,name,blocks_json,updated_at)
           VALUES(?,?,?,?)
           ON CONFLICT(preset_id) DO UPDATE SET
             name=excluded.name, blocks_json=excluded.blocks_json,
             updated_at=excluded.updated_at''',
        (NEW_ID, NEW_NAME, normalized_json, now),
    )
    conn.commit()

    # Verification: source untouched, new preset exists, alternatives retained.
    source_after = conn.execute(
        "SELECT blocks_json FROM studio_preset_rows WHERE preset_id='default'"
    ).fetchone()[0]
    new_row = conn.execute(
        'SELECT name,blocks_json FROM studio_preset_rows WHERE preset_id=?',
        (NEW_ID,),
    ).fetchone()
    new_blocks = json.loads(new_row[1])
    assert source_after == original_json
    assert any(b['id'] == 'final_prose_style_anime' and b['enabled'] for b in new_blocks)
    assert any(b['id'] == 'final_prose_style_universal' and not b['enabled'] for b in new_blocks)
    assert any(b['id'] == 'final_prose_style_ao3' and not b['enabled'] for b in new_blocks)
    assert not next(b for b in new_blocks if b['id'] == 'pregen_narrative_engine')['enabled']
    print(json.dumps({
        'backup': BACKUP,
        'preset_id': NEW_ID,
        'name': new_row[0],
        'source_unchanged': source_after == original_json,
        'source_blocks': len(json.loads(original_json)),
        'new_blocks': len(new_blocks),
        'removed_legacy_ids': sorted(remove_ids),
        'disabled_style_alternatives': [
            b['id'] for b in new_blocks
            if b['id'] in {'final_prose_style_universal','final_prose_style_ao3'}
            and not b['enabled']
        ],
    }, ensure_ascii=False, indent=2))
finally:
    conn.close()
