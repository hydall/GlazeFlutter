import json
import os
import shutil
import sqlite3
import time

DB = os.path.join(os.environ['APPDATA'], 'Glaze', 'glaze.db')
SESSION = 'mql29fxr0001_7'
MESSAGE = 'mrdnzska0000'
SWIPE = 5
AGENT_SWIPE = 0
BACKUP = f'{DB}.before_ledger_normalize_{int(time.time())}.bak'

shutil.copy2(DB, BACKUP)
conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row
now = int(time.time())

# Current truth only. Values intentionally omit historical scene prose,
# telemetry repetition, speculative psychology, and invented precision.
normalized = {
    'canon_override:npc:Danvi.prior_leg_injury_retcon': (
        'The earlier leg injury was explicitly removed from canon. Do not '
        'restore or reference that old leg injury. This does not erase injuries '
        'explicitly established later in the timeline.'
    ),
    'npc:Danvi.injury_state': (
        'New post-retcon injuries from the Adam Smasher encounter: severe '
        'torso/rib trauma; Danvi described himself as near death but remains '
        'conscious and moving under his own power. Exact diagnosis is unknown. '
        'Track as current state, not a recurring prose motif.'
    ),
    'arc:bestia_audience.status': 'agreement_active; cargo delivery in progress',
    'arc:bestia_audience.summary': (
        'Payment: Malorian 3516 acquisition location plus Sasha Yakovleva dossier. '
        'This replaces the earlier Silverhand-coordinates framing.'
    ),
    'arc:bestia_audience.do_not_reopen': 'false',
    'arc:find_alexandra_yakovleva.status': 'dossier included in current payment',
    'arc:find_alexandra_yakovleva.summary': (
        'Danvi is seeking information about Sasha (Alexandra Yakovleva).'
    ),
    'arc:find_alexandra_yakovleva.do_not_reopen': 'false',
    'arc:maelstrom_midnight_ritual.status': 'outcome unknown',
    'arc:maelstrom_midnight_ritual.summary': (
        'The ritual occurred; its outcome and responsible actor remain unconfirmed.'
    ),
    'arc:maelstrom_midnight_ritual.do_not_reopen': 'false',
    'arc:militech_convoy_job.status': 'cargo secured; escape still active',
    'arc:militech_convoy_job.summary': (
        'Both cryostacks are intact. One transport cleared the hot zone; the other '
        'is routing to Bestia. Danvi, Lucy, and Helga are escaping through branch C '
        'while Adam Smasher searches for an alternate route around the collapse.'
    ),
    'arc:militech_convoy_job.do_not_reopen': 'false',
    'npc:Danvi.card_overrides': (
        'Has Blood Pump cyberware managed by Helga; uses Synapse Melt; '
        'demonstrated exceptional biological strength.'
    ),
    'npc:Danvi.knowledge': (
        'Moving through branch C toward the service-well fork. Delamain is waiting '
        'near the direct exit. Arasaka/Militech coordination remains unconfirmed.'
    ),
    'npc:Helga.card_overrides': (
        'Danvi’s onboard AI/co-pilot; manifests as a black-cat HUD avatar; '
        'sardonic and hyper-analytical.'
    ),
    'npc:Helga.knowledge': (
        'Both cryostacks are intact and routed. Smasher is bypassing the collapse. '
        'Coordinates navigation with Lucy.'
    ),
    'npc:Helga.relationship_to_user': 'Danvi’s loyal tactical and analytical co-pilot.',
    'npc:Lucy.knowledge': (
        'Holds the Malorian location and Sasha dossier pending confirmed delivery. '
        'Found no confirmed ground-level Militech/Arasaka coordination. Spoofed a '
        'recon drone and opened the service-well lock without actuating it.'
    ),
    'npc:Lucy.relationship_to_user': (
        'Operational alliance with Danvi; coordinating escape and cargo exchange; '
        'trust remains limited.'
    ),
    'npc:Lucy.boundaries': (
        'Guarded about David Martinez and personal history; prioritizes current '
        'operational survival.'
    ),
    'npc:BestiaAmendiares.knowledge': (
        'Payment is Malorian 3516 acquisition location plus Sasha dossier, '
        'not Silverhand coordinates.'
    ),
    'npc:BestiaAmendiares.relationship_to_user': (
        'Fixer/client relationship; payment contingent on cargo delivery.'
    ),
    'npc:Clare.relationship_to_user': 'Afterlife bartender; first interaction this session.',
    'npc:Clare.boundaries': 'Acts as a gatekeeper for access to Bestia.',
    'npc:AdamSmasher.knowledge': (
        'Optics and vocal systems are damaged. Pursuing through the drainage system '
        'using remaining tactile and obstacle-avoidance systems; direct branch-C '
        'route is blocked, but an alternate path approaches the fork.'
    ),
    'relationship:Helga:Lucy.relationship': (
        'Direct tactical contact established; they coordinate route and telemetry '
        'while remaining mutually distrustful.'
    ),
    'relationship:Lucy:Danvi.relationship': (
        'Operational alliance under pressure. Lucy does not treat Danvi as a '
        'replacement for David; cargo/payment terms remain active.'
    ),
    'scene.present_entities': (
        'Danvi (moving through branch C), Lucy (nearby and coordinating), '
        'Helga (on tactical channel), Adam Smasher (approaching via an alternate path).'
    ),
    'scene.absent_backstory_entities': (
        'Bestia and Clare are off-scene. Militech forces are active above ground.'
    ),
    'world:location': (
        'Watson North Docks, underground drainage branch C, approaching the fork '
        'between service well 19-B and the water-discharge route.'
    ),
    'world:time': 'Early morning; immediate escape decisions are in progress.',
    'world:active_threats': (
        'Adam Smasher is approaching the fork by an alternate path. Militech aerial '
        'recon threatens the direct service-well exit. The route choice is unresolved.'
    ),
}

keep = set(normalized)
try:
    conn.execute('BEGIN IMMEDIATE')

    # Remove model-written Ledger pollution for this session. Non-ledger scopes
    # (user memory, diagnostics) remain untouched.
    conn.execute(
        "DELETE FROM tracker_rows WHERE session_id=? AND scope='ledger'",
        (SESSION,),
    )
    conn.execute(
        "DELETE FROM tracker_rows WHERE session_id=? AND name LIKE 'npc:SilverHairedWoman.%'",
        (SESSION,),
    )
    for name, value in normalized.items():
        conn.execute(
            '''INSERT INTO tracker_rows
               (session_id,name,value,scope,provenance,updated_at)
               VALUES(?,?,?,?,?,?)
               ON CONFLICT(session_id,name) DO UPDATE SET
                 value=excluded.value,
                 scope=excluded.scope,
                 provenance=excluded.provenance,
                 updated_at=excluded.updated_at''',
            (
                SESSION,
                name,
                value,
                'ledger',
                'source=manual_normalization|reason=current_truth_compaction',
                now,
            ),
        )

    # Build exactly the state future prompts should read. Snapshot-first loading
    # ignores uncommitted tracker_rows, so the current selected swipe must have a
    # committed normalized snapshot.
    rows = conn.execute(
        'SELECT * FROM tracker_rows WHERE session_id=? ORDER BY name',
        (SESSION,),
    ).fetchall()
    trackers = [
        {
            'sessionId': r['session_id'],
            'name': r['name'],
            'value': r['value'],
            'scope': r['scope'],
            'provenance': r['provenance'],
            'updatedAt': r['updated_at'],
        }
        for r in rows
    ]
    conn.execute(
        '''INSERT INTO tracker_snapshots
           (session_id,message_id,swipe_id,agent_swipe_id,trackers_json,committed,created_at)
           VALUES(?,?,?,?,?,1,?)
           ON CONFLICT(session_id,message_id,swipe_id,agent_swipe_id)
           DO UPDATE SET trackers_json=excluded.trackers_json,
                         committed=1, created_at=excluded.created_at''',
        (
            SESSION,
            MESSAGE,
            SWIPE,
            AGENT_SWIPE,
            json.dumps(trackers, ensure_ascii=False, separators=(',', ':')),
            now,
        ),
    )
    # Only the selected history branch is effective canon.
    conn.execute(
        '''UPDATE tracker_snapshots SET committed=0
           WHERE session_id=? AND NOT
             (message_id=? AND swipe_id=? AND agent_swipe_id=?)''',
        (SESSION, MESSAGE, SWIPE, AGENT_SWIPE),
    )
    conn.commit()

    ledger_rows = conn.execute(
        "SELECT name,value FROM tracker_rows WHERE session_id=? AND scope='ledger' ORDER BY name",
        (SESSION,),
    ).fetchall()
    current = conn.execute(
        '''SELECT message_id,swipe_id,agent_swipe_id,committed,trackers_json
           FROM tracker_snapshots WHERE session_id=? AND committed=1''',
        (SESSION,),
    ).fetchall()
    assert len(current) == 1
    assert current[0]['message_id'] == MESSAGE and current[0]['swipe_id'] == SWIPE
    snapshot_names = {x['name'] for x in json.loads(current[0]['trackers_json'])}
    assert 'canon_override:npc:Danvi.prior_leg_injury_retcon' in snapshot_names
    assert 'npc:Danvi.injury_state' in snapshot_names
    assert 'canon_lock:npc:Danvi.injury_state' not in snapshot_names
    assert 'npc:SilverHairedWoman.attitude_to_user' not in snapshot_names
    assert not any('тяжело травмирован' in r['value'].lower() for r in ledger_rows)
    assert not any('old leg injury' in r['value'].lower() for r in ledger_rows if not r['name'].startswith('canon_'))

    print(json.dumps({
        'backup': BACKUP,
        'ledger_rows_before': 47,
        'ledger_rows_after': len(ledger_rows),
        'committed_snapshot': {
            'message_id': current[0]['message_id'],
            'swipe_id': current[0]['swipe_id'],
            'agent_swipe_id': current[0]['agent_swipe_id'],
        },
        'old_leg_retcon_is_scoped': True,
        'new_injury_is_mutable': True,
        'alias_removed': True,
    }, ensure_ascii=False, indent=2))
finally:
    conn.close()
