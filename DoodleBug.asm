// ======================================================================
//  DOODLE BUG  -  Commodore VIC-20 (unexpanded)   (C) Mastertronics
//  Disassembled from 'Doodle Bug.prg' (PAL / IKARI cracked release)
//  and re-commented for KickAssembler, with an input-handling fix, a slower
//  menu key repeat and the cracker's wasted bytes removed (see 'FIX' notes).
// ======================================================================
//
//  THE GAME
//    A Pac-Man style maze game.  You are a bug that eats every dot in
//    the maze (209 of them) while enemy bugs (1-5, your choice) chase you.
//    Your joystick FIRE button with a direction fires a 'bug spray' bomb:
//    it leaves a cloud on your square and any enemy that walks into the
//    cloud is killed (+100 points, it respawns in the middle).
//    Revolving doors in the maze swing through 90 degrees when pushed.
//    The side exits of the maze wrap round (left edge <-> right edge).
//    Clearing the maze gives an extra bomb and a harder level: one more
//    enemy, and once there are five enemies, a faster game.  The next level
//    is played on the next of the three mazes (they cycle).
//
//  CONTROLS   Title screen:  F1 = number of enemies (1-5)
//                            F3 = game speed (1-6)
//                            Joystick FIRE = start
//             In game:       Joystick = move,  FIRE + up/down/left = bomb
//
//  MEMORY MAP (unexpanded VIC-20)
//    $1001-$100D   BASIC stub:  10 SYS 4535
//    $100E-$11B6   title screen / menu
//    $11B7-$11BC   entry point ('start' = SYS 4535)
//    $11BD-$1262   text strings, tunes, speed table, two variables
//    $1263-$12B8   main loop
//    $12B9-$13B3   level complete, level reset
//    $13B4-$14FF   enemy killed, player dies, cell drawing
//    $1500-$1701   enemy movement / AI
//    $1702-$1983   player movement, bombs, doors, dots
//    $1984-$19DF   score handling
//    $19E0-$1A50   level number display, game over, tune player
//    $1A51-$1AEC   maze unpacking, door drawing
//    $1AED-$1B12   game variables (enemy tables, lives, score, hi-score)
//    $1B13-$1BF6   packed mazes (three): wall bitmaps, door tables, per-maze values
//    $1BF7-$1BFF   FREE - 9 bytes
//    $1C00-$1DD7   custom character set (59 characters, screen codes $00-$3A)
//    $1DD8-$1DFF   row offset table and more game variables (full)
//    $1E00-$1FF9   screen memory   $9600-$97F9   colour memory
//
//  (The original program filled $1001-$1DFF completely.  This version is
//  functionally the same game, with these changes:
//   - the cracker's second BASIC line, leftover data, unused bytes,
//     write-only variables, decimal-mode clears and no-ops are removed
//   - the 440-byte maze is stored as a 56-byte wall bitmap plus a few rules
//   - TWO NEW MAZES have been added; the game cycles maze 1 -> 2 -> 3 -> 1 ...
//     each time a level is cleared.  A new game starts on the maze given by
//     START_MAZE (currently maze 3 for testing; set it to 0 for the normal
//     order starting with the original maze)
//   - presentation: LEVEL number on the status row, a GAME OVER message, a
//     title tune (FIRE skips it), a level-complete jingle and a game-over tune
//   - joystick reading, slower menu key repeat, BASIC-banner clear and a
//     speed-wrap bug are fixed.
//  See the 'FIX' comments.)
//
//  SCREEN LAYOUT (22 x 23 characters)
//    row 0       SCORE / HISCORE labels
//    row 1       score and hi-score digits
//    row 2       lives, bombs and level number
//    rows 3-22   the 22 x 20 maze
//    The maze is addressed as two 220-byte halves (MAZE_TOP = $1E42 for maze
//    rows 0-9 and MAZE_BOTTOM = $1F1E for rows 10-19) so a single 8-bit index
//    can reach every cell.  Cell address = half base + rowOffset[row] + col.
//
//  CHARACTER SET (screen codes)
//    $00 splat    $01-$1A letters A-Z    $1B-$1E door arms    $1F door hub
//    $20 space    $21 wall    $22 dot    $23-$26 player (4 frames)
//    $27-$28 enemy (2 frames)    $29 bomb cloud    $2A-$2D squashed player
//    $2E small dot    $2F ring    $30-$39 digits    $3A ':'

// ---- Hardware -------------------------------------------------------
.label VIC_CHARBASE  = $9005  // screen / character memory pointers
.label VIC_BASS      = $900A  // bass voice ($80+ = on)
.label VIC_ALTO      = $900B  // alto voice
.label VIC_SOPRANO   = $900C  // soprano voice
.label VIC_NOISE     = $900D  // noise voice
.label VIC_VOLUME    = $900E  // volume (bits 0-3) / auxiliary colour
.label VIC_COLOURS   = $900F  // background / border colour
.label VIA1_PORTA    = $911F  // joystick: up/down/left/fire (active low)
.label VIA2_PORTB    = $9120  // keyboard rows / joystick RIGHT on bit 7
.label VIA2_DDRB     = $9122  // port B data direction
.label KEY_PRESSED   = $C5    // KERNAL: matrix code of the key held
.const START_MAZE = 2           // maze a new game starts on: 0 = maze 1, 1 = maze 2, 2 = maze 3
                                // (set to 2 for now so that maze 3 can be tried first; use 0 for the normal order)
.label MAZE_TOP      = $1E42  // screen address of maze row 0 (rows 0-9 follow)
.label MAZE_BOTTOM   = $1F1E  // screen address of maze row 10 (rows 10-19 follow)
.label fireFlag      = enemyCol+1  // $FF = a bomb was fired on the previous move (shares the unused enemyCol[1] byte, as in the original)
.label shiftTop       = $F9    // zero page work bytes used by draw_maze (free on the VIC-20)
.label shiftBottom    = $FA
.label doorCount      = $FB
.label screenPtr      = $FC    // $FC/$FD
.label colourPtr      = $FE    // $FE/$FF
.label MAZE_TOP_COL  = $9642  // colour RAM for MAZE_TOP
.label MAZE_BOTTOM_COL= $971E  // colour RAM for MAZE_BOTTOM

// ---- FIX (not in the original) --------------------------------------
// The original compared the whole of $911F after ORA #$40 with $7E/$5E/etc.
// Bits 0, 1 and 7 of that port are serial-bus lines, whose state depends on
// the IEC bus / drive, so on many setups (e.g. VICE) the joystick was never
// recognised.  ReadJoystick keeps only the four direction/fire bits (2-5) and
// forces the rest to the values the game expects, so idle = $7E, fire = $5E,
// up = $7A, down = $76, left = $6E exactly as before.
.macro ReadJoystick() {
    lda  VIA1_PORTA
    and  #$3C
    ora  #$42
}

.pc = $1001 "Doodle Bug"

// BASIC stub:   10 SYS 4535   (= $11B7, the 'start' label below)
// (The original also had a second BASIC line, '*** PAL-IKARI ***', and 93 bytes
// of leftover loader data after it; neither was used and both were removed.)
    .word $100C             // pointer to next BASIC line
    .word 10                // line number 10
    .byte $9E               // SYS token
    .text " 4535"           // = start (checked by the .errorif at 'start')
    .byte $00               // end of line
    .word $0000             // end of program

// title_screen
// Sets up the video chip and draws the title / menu screen.  Called once at
// start-up and again whenever the game ends (all lives lost).
// It then loops until the player presses FIRE, letting them change the number
// of enemies (F1) and the game speed (F3) while they wait.
title_screen:
    ldx  #$FF                     // $FF: screen memory at $1E00, character set at $1C00 (our custom set)
    stx  VIC_CHARBASE
    ldx  #$19                     // $19: white background, white border, normal video
    stx  VIC_COLOURS
    ldx  #$00
    lda  #$20                     // A = space (screen code $20)
ts_clear:
    sta  $1E00,x                  // FIX: also clear rows 0-2 (the original left the BASIC banner, e.g. 'M BASIC', showing between the labels)
    sta  MAZE_TOP,x               // clear the 20x22 play area: 440 bytes, done as two halves of 220
    sta  MAZE_BOTTOM,x
    inx
    cpx  #$DC                     // 220 ($DC) bytes done?
    bne  ts_clear

// Colour the three status rows: row 0 blue, row 1 purple, row 2 cyan.
// (The original has 'LDX $00' - a zero-page read - instead of 'LDX #$00', so X
// starts with whatever is in location 0 and the loop runs through 256 values
// before reaching $16.  It just paints some extra colour RAM; harmless.)
    ldx  $00                      // original code: zero-page read, not immediate (see above)
ts_colour_rows:
    lda  #$06                     // colour 6 = blue   -> row 0 (SCORE / HISCORE labels)
    sta  $9600,x
    lda  #$04                     // colour 4 = purple -> row 1 (score values)
    sta  $9616,x
    lda  #$03                     // colour 3 = cyan   -> row 2 (lives / bombs)
    sta  $962C,x
    inx
    cpx  #$16
    bne  ts_colour_rows

// Row 0: 'SCORE' at column 0 and 'HISCORE' at column 15
    ldx  #$00
ts_labels:
    lda  txtScore,x
    sta  $1E00,x
    lda  txtHiScore,x
    sta  $1E0F,x
    inx
    cpx  #$07
    bne  ts_labels

// Row 1: current score (col 0) and hi-score (col 15), six digits each.
// Seven bytes are copied; the seventh is overwritten with '0' just below, so
// the numbers shown always carry an extra trailing zero.
    ldx  #$00
ts_scores:
    lda  score,x
    sta  $1E16,x
    lda  hiScore,x
    sta  $1E25,x
    inx
    cpx  #$07
    bne  ts_scores
    lda  #$30                     // '0' ...
    sta  $1E1C                    // ... trailing zero after the score ...
    sta  $1E2B                    // ... and after the hi-score
    clc                           // clc/cld: the original does this before every ADC

// Row 2: lives (player icon, colon, digit) and bombs (cloud icon, colon, digit)
    ldx  #$23                     // $23 = player character
    stx  $1E2C
    ldx  #$3A                     // $3A = ':' character
    stx  $1E2D
    stx  $1E32
    lda  lives                    // lives is a plain number; add '0' to get the digit
    adc  #$30
    sta  $1E2E
    ldx  #$29                     // $29 = bomb / spray-cloud character
    stx  $1E31
    lda  bombs                    // bombs left
    adc  #$30
    sta  $1E33
    ldx  #$05                     // 'LEVEL ' on the right of row 2 (columns 14-19) ...
ts_level_label:
    lda  txtLevel,x
    sta  $1E3A,x
    dex
    bpl  ts_level_label
    jsr  show_level               // ... followed by the two level digits (columns 20-21)

// Menu text.  Each line is copied to the screen and coloured:
//   row 6  col 5    ' DOODLE BUG '         red
//   row 9  col 2    '(C) MASTERTRONICS'    purple
//   row 13          'NUMBER OF DEVILS  F1' green
//   row 16          'SPEED OF PLAY     F3' green
//   row 20 col 4    'FIRE TO START'        red
    ldx  #$00
ts_title:
    lda  txtTitle,x
    sta  $1E89,x
    lda  #$02                     // colour 2 = red
    sta  $9689,x
    inx
    cpx  #$0C
    bne  ts_title
    ldx  #$00
ts_copyright:
    lda  txtCopyright,x
    sta  $1EC8,x
    lda  #$04                     // colour 4 = purple
    sta  $96C8,x
    inx
    cpx  #$11
    bne  ts_copyright
    ldx  #$00
ts_menu:
    lda  txtDevils,x
    sta  MAZE_BOTTOM,x
    lda  txtSpeed,x
    sta  $1F60,x
    lda  #$05                     // colour 5 = green
    sta  MAZE_BOTTOM_COL,x
    sta  $9760,x
    inx
    cpx  #$16
    bne  ts_menu
    ldx  #$00
ts_fire_text:
    lda  txtFire,x
    sta  $1FBC,x
    lda  #$02                     // colour 2 = red
    sta  $97BC,x
    inx
    cpx  #$0D
    bne  ts_fire_text

// VIA2 port B direction register: all outputs, so the keyboard columns can be
// scanned (the KERNAL puts the key code in $C5).  Then initial menu values:
// enemyLimit = 2 (=> 1 enemy; enemies = enemyLimit - 1) and speed index 0.
    ldx  #$FF                     // $FF = all bits outputs
    stx  VIA2_DDRB
    ldx  #$02                     // enemyLimit = 2
    stx  enemyLimit
    ldx  #$00                     // gameDelay holds a speed INDEX 0-5 while on this screen
    stx  gameDelay

// Menu loop.  First show the two chosen values:
// number of enemies = enemyLimit + $2F  (i.e. '0' + enemyLimit - 1)
    lda  #$20
    sta  tuneSkip                 // the title tune can be skipped with FIRE
    ldx  #tuneTitle-tuneData
    jsr  play_tune
ts_key_loop:
    lda  enemyLimit
    clc
    adc  #$2F                     // A = enemyLimit + $2F  ('1'..'5')
    sta  $1F30                    // row 13, column 18
    lda  #$02                     // colour red
    sta  $9730
    lda  gameDelay                // speed = index + $31  ('1'..'6')
    adc  #$31
    sta  $1F72                    // row 16, column 18
    lda  #$02
    sta  $9772
    ldx  #$00                     // busy-wait about a third of a second (256 x 256 loops) so keys do not repeat too fast
ts_delay_outer:
    ldy  #$00
ts_delay_inner:
    iny
    cpy  #$00
    bne  ts_delay_inner
    inx
    cpx  pollLimit                // FIX: poll the keys every ~0.07 s (the original waited 0.45 s and missed taps) ...
    bne  ts_delay_outer
    ldx  KEY_PRESSED              // KERNAL: matrix code of the key currently held
    cpx  #$27                     // $27 = F1: step the number of enemies
    bne  ts_check_f3
    ldy  enemyLimit
    iny
    cpy  #$07
    bne  ts_f1_store
    ldy  #$02                     // wraps from 6 back to 2
ts_f1_store:
    sty  enemyLimit
ts_check_f3:
    cpx  #$2F                     // $2F = F3: step the speed index
    bne  ts_check_fire
    ldy  gameDelay
    iny
    cpy  #$06
    bne  ts_f3_store
    ldy  #$00                     // wraps from 5 back to 0
ts_f3_store:
    sty  gameDelay

// Poll the joystick port.  OR-ing with $40 masks the cassette-sense bit:
// idle reads $7E and FIRE alone reads $5E.  Not fire? go round again.
ts_check_fire:
    lda  #$28                     // ... but after F1/F3 has changed something wait ~0.34 s before the next poll,
    cpx  #$27                     // so holding the key steps the value at a comfortable rate
    beq  ts_slow_poll
    cpx  #$2F
    bne  ts_set_poll
ts_slow_poll:
    lda  #$C0
ts_set_poll:
    sta  pollLimit
    ReadJoystick()               // VIA1 port A: up / down / left / fire (active low)
    cmp  #$5E                     // $5E = fire pressed
    beq  ts_start_game
    jmp  ts_key_loop

// FIRE pressed.  Reset the score (on screen and in the variable) to '000000'
ts_start_game:
    ldx  #$00
    lda  #$30                     // ASCII '0'
ts_zero_score:
    sta  $1E16,x                  // on-screen score ...
    sta  score,x                  // ... and the score variable
    inx
    cpx  #$06
    bne  ts_zero_score

// Turn the chosen speed index into the real delay count from speedTable
    ldx  gameDelay
    lda  speedTable,x             // bigger delay = slower game
    sta  gameDelay

// Wait until FIRE is released (joystick idle again), then start the game
ts_wait_release:
    ReadJoystick()
    cmp  #$7E                     // $7E = idle
    bne  ts_wait_release
    lda  #START_MAZE
    sta  mazeNumber               // every new game starts on this maze (see START_MAZE)
    lda  #$30
    sta  levelTens                // ... and on level 01
    lda  #$31
    sta  levelUnits
    jsr  reset_level              // lay out the maze, place player and enemies
    lda  #$05                     // start with 5 lives ...
    sta  lives
    sta  bombs                    // ... and 5 bombs

// Make bit 7 of VIA2 port B an input again: that is where the joystick's RIGHT
// switch is read during play.
    ldx  #$7F                     // %01111111
    stx  VIA2_DDRB
    rts

// === BASIC SYS entry point ('start'; was $11EE = SYS 4590 in the original) ===
start:
.errorif start != 4535, "start has moved: update the SYS address in the BASIC stub"
// Show the title screen, then run the main loop for ever.
    jsr  title_screen             // title screen (returns when the player presses fire)
    jmp  main_loop                // never returns


// ======================================================================
// Text strings, stored as SCREEN CODES (A=1 ... Z=26, space=32, digits=$30+)
// The strings that end in a character code of 6 followed by '1' / '3'
// ('F' then '1') are the F1 / F3 key names.  Codes $A8 and $A9 are the '(' and ')'
// of '(C)'; being above $7F, they fetch glyphs from outside the custom set.
// ======================================================================
.encoding "screencode_upper"
txtScore:     .text "SCORE  "              // $11F8
txtHiScore:   .text "HISCORE"              // $11FF
txtTitle:     .text " DOODLE BUG "         // $1206
txtCopyright: .byte $A8                    // $1212  "(" ...
               .text "C"
               .byte $A9                    // ... ")"
               .text " MASTERTRONICS"
txtDevils:    .text "NUMBER OF DEVILS    F1"   // $1223
txtSpeed:     .text "SPEED OF PLAY       F3"   // $1239
txtFire:      .text "FIRE TO START"        // $124F
txtLevel:     .text "LEVEL "               // status row 2, columns 14-19 (then two digits)
txtGameOver:  .text "GAME OVER"            // printed on the maze when the last life is lost

// ---- Tunes (see play_tune).  Note values are for the soprano voice, PAL.
.const C4=190; .const E4=203; .const G4=212; .const A4=217; .const FS4=209
.const C5=223; .const D5=227; .const E5=230; .const G5=234; .const A5=236; .const C6=239
.const REST=1
tuneData:
tuneTitle:                                   // title screen: a quick rising / falling bug motif
    .byte C5,4, E5,4, G5,4, C6,8, G5,4, E5,4, C5,12, 0
tuneLevel:                                   // level complete: a short fanfare
    .byte C5,4, E5,4, G5,4, C6,6, REST,2, G5,3, C6,14, 0
tuneGameOver:                                // game over: falling notes, then a pause so the message stays up
    .byte E5,8, C5,8, A4,8, FS4,8, C4,20, REST,30, 0

// speedTable: game-delay values for speed settings 1..6 (bigger = slower)
// gameDelay later holds the chosen value; main_loop waits gameDelay x 256 loops.
speedTable:   .byte $33,$29,$1F,$15,$0B,$01     // $125C

gameDelay:    .byte $00            // $1284  speed index, then delay count (see speedTable)
phase:        .byte $01            // $1285  0,1,2 tick counter: enemies skip phase 0

// === MAIN LOOP ===
// One pass is one game 'tick':
//   1. move the player (reads the joystick)
//   2. move the enemies - but only on 2 ticks out of every 3, so the player is quicker
//   3. fixed short delay
//   4. silence the sound voices
//   5. speed delay: gameDelay x 256 loops (this is the SPEED setting)
//   6. refresh the bomb and lives digits on screen
main_loop:
    jsr  player_update            // joystick, bomb, player movement and drawing
    ldx  phase                    // phase counts 0,1,2,0,1,2 ...
    inx
    cpx  #$03
    bne  ml_phase_ok              // wrap at 3
    ldx  #$00
ml_phase_ok:
    stx  phase
    cpx  #$00                     // phase 0: leave the enemies alone this tick
    beq  ml_delay
    jsr  move_enemies             // phases 1 and 2: move every enemy one step
ml_delay:
    ldx  #$00                     // fixed delay: 70 x 256 loops
ml_delay_outer:
    ldy  #$00
ml_delay_inner:
    iny
    cpy  #$00
    bne  ml_delay_inner
    inx
    cpx  #$46
    bne  ml_delay_outer
    ldx  #$00                     // silence the soprano, alto and volume registers
    stx  VIC_SOPRANO
    stx  VIC_ALTO
    stx  VIC_VOLUME
    ldx  #$00                     // speed delay: gameDelay x 256 loops
ml_speed_outer:
    ldy  #$00
ml_speed_inner:
    iny
    cpy  #$00
    bne  ml_speed_inner
    inx
    cpx  gameDelay
    bne  ml_speed_outer
    lda  bombs                    // bombs digit ...
    clc
    adc  #$30
    sta  $1E33
    lda  lives                    // ... and lives digit
    adc  #$30
    sta  $1E2E
    jsr  show_level               // ... and the level number
    jmp  main_loop                // round again

// level_complete
// Every dot has been eaten.  The player is rewarded and the game gets harder:
//   - enemyLimit goes up by one (one more enemy), to a maximum of 6 (5 enemies)
//   - once at the maximum, the game gets faster instead (delay -= 10, minimum 1)
//   - one more bomb (maximum 9)
//   - a screen-flash / falling-tone effect plays, then the maze is rebuilt
level_complete:
    ldx  enemyLimit               // (a value below $80 leaves the voices switched off)
    stx  VIC_ALTO
    stx  VIC_SOPRANO
    inx                           // enemyLimit + 1 ...
    cpx  #$07                     // ... 7 would be too many?
    bne  lc_enemies_done
    ldx  #$06                     // yes: clamp to 6 and speed the game up instead
    lda  gameDelay                // gameDelay - 10, but never below 1 (the fastest speed)
    sec
    sbc  #$0A
    bcc  lc_fastest               // FIX: the original used CMP #$64 / BMI here, which let a small delay
    bne  lc_store_speed           // wrap round to a huge one (e.g. $01-10 = $F7), making the game very slow;
lc_fastest:                       // a result of 0 would also mean the SLOWEST delay (256 loops)
    lda  #$01
lc_store_speed:
    sta  gameDelay
lc_enemies_done:
    stx  enemyLimit               // store the new enemy limit
    ldx  bombs                    // bombs + 1, capped at 9
    inx
    cpx  #$0A
    bne  lc_bombs_done
    ldx  #$09
lc_bombs_done:
    stx  bombs                    // show the new bomb count
    txa
    clc
    adc  #$30
    sta  $1E33
    lda  #$0F                     // full volume
lc_flash_outer:
    ldy  #$FF                     // flash the screen colours and sweep the soprano down
lc_flash_mid:
    ldx  #$00
lc_flash_inner:
    inx                           // tiny delay
    cpx  #$00
    bne  lc_flash_inner
    dey
    sty  VIC_COLOURS
    sty  VIC_SOPRANO
    cpy  #$7F
    bne  lc_flash_mid
    sec                           // fade the volume out one step per sweep
    sbc  #$01
    cmp  #$FF
    sta  VIC_VOLUME
    bne  lc_flash_outer
    lda  #$19                     // back to white screen / border
    sta  VIC_COLOURS
    ldx  levelUnits               // level number + 1 (two ASCII digits, stops at 99)
    inx
    cpx  #$3A
    bne  lc_level_store
    ldx  #$30
    inc  levelTens
lc_level_store:
    stx  levelUnits
    lda  levelTens
    cmp  #$3A
    bne  lc_level_ok
    lda  #$39
    sta  levelTens
    sta  levelUnits               // 99 is the highest shown
lc_level_ok:
    lda  #$00
    sta  tuneSkip                 // the jingle cannot be skipped
    ldx  #tuneLevel-tuneData
    jsr  play_tune                // level-complete jingle
    ldx  mazeNumber               // next maze: 1 -> 2 -> 3 -> 1 ...
    inx
    cpx  #$03
    bcc  lc_maze_store
    ldx  #$00
lc_maze_store:
    stx  mazeNumber
    jmp  reset_level              // redraw the maze (this also resets dotsEaten)

// reset_level
// Puts everything in its starting state for a new level or after losing a life:
//   - enemy directions, start squares and 'standing on' dots
//   - player at row 14, column 10, bomb flag cleared, maze redrawn
// The enemy tables are indexed by enemy number 2..6 (entries 0 and 1 are not used).
reset_level:
    ldx  #$00

// enemyCol[1..3] = 1 (left edge), enemyDir[0..2] = 5 (right)
rl_dirs_a:
    lda  #$01                     // column 1
    sta  enemyCol+1,x
    lda  #$05                     // direction 5 = right
    sta  enemyDir,x
    inx
    cpx  #$03
    bne  rl_dirs_a

// enemyCol[4..6] = 20 (right edge), enemyDir[3..5] = 2 (left)
    ldx  #$03
rl_dirs_b:
    lda  #$14                     // column 20
    sta  enemyCol+1,x
    lda  #$02                     // direction 2 = left
    sta  enemyDir,x
    inx
    cpx  #$06
    bne  rl_dirs_b

// Enemy start rows: 1, 7 and 18 on each side - so enemies 2-6 start at
// (7,1) (18,1) (1,20) (7,20) (18,20) as row,column.
    lda  #$01
    sta  enemyRow+1
    sta  enemyRow+4
    lda  #$07
    sta  enemyRow+2
    sta  enemyRow+5
    lda  #$12
    sta  enemyRow+3
    sta  enemyRow+6

// Player starts at row 14, column 10.  dotsEaten = 0
    lda  #$00                     // dotsEaten = 0
    sta  dotsEaten
    lda  #$0E                     // player row
    sta  playerRow
    lda  #$0A                     // player column
    sta  playerCol

// Every enemy starts out standing on a dot ($22)
    ldx  #$01
    lda  #$22                     // $22 = dot
rl_under:
    sta  enemyUnder+1,x           // enemyUnder[1..6] (this also overwrites fireFlag)
    inx
    cpx  #$07
    bne  rl_under
    jsr  draw_maze                // copy the maze to the screen and colour it

// pause (65,536 loops) so the player sees the maze before play starts
    ldx  #$00
rl_delay_outer:
    ldy  #$00
rl_delay_inner:
    iny
    cpy  #$00
    bne  rl_delay_inner
    inx
    cpx  #$00
    bne  rl_delay_outer
    rts

// kill_enemy   (X = enemy number)
// An enemy has walked into the bomb's spray cloud.  A falling-pitch noise
// plays, the enemy is erased, respawned in the middle of the maze (row 9,
// column 10), and the player scores 100 points.
kill_enemy:
    stx  tempRow                  // remember which enemy
    lda  #$0F                     // volume 15
    sta  VIC_VOLUME
    lda  #$E6                     // pitch starts at $E6 and falls by 10 each step until $82
ke_sweep:
    sta  VIC_SOPRANO
    sta  VIC_ALTO
    ldx  #$00                     // short wait between steps
ke_wait_outer:
    ldy  #$00
ke_wait_inner:
    iny
    cpy  #$00
    bne  ke_wait_inner
    inx
    cpx  #$14
    bne  ke_wait_outer
    sec
    sbc  #$0A
    cmp  #$82
    bne  ke_sweep
    lda  #$00                     // silence
    sta  VIC_VOLUME
    sta  VIC_SOPRANO
    sta  VIC_ALTO
    jsr  erase_enemy              // blank the enemy's old cell
    lda  #$09                     // respawn at row 9 ...
    sta  enemyRow,x
    lda  #$0A                     // ... column 10
    sta  enemyCol,x
    lda  #$01                     // +1 on the hundreds digit
    clc
    adc  score+3
    sta  score+3
    jsr  update_score             // carry and refresh the on-screen score
    ldx  tempRow                  // X = enemy number again
    lda  #$20                     // it is no longer standing on anything
    sta  enemyUnder,x
    rts

// erase_enemy   (X = enemy number)
// Blank the screen cell the enemy occupies.
erase_enemy:
    ldx  tempRow                  // X = enemy number (kill_enemy saved it in tempRow)
    lda  enemyRow,x               // Y = rowOffset[row] + col
    tay
    lda  rowOffset,y
    clc
    adc  enemyCol,x
    tay
    lda  enemyRow,x
    cmp  #$0A                     // top half of the maze (rows < 10) or the bottom half?
    bpl  ee_lower
    lda  #$20                     // space
    sta  MAZE_TOP,y
    rts
ee_lower:
    lda  #$20
    sta  MAZE_BOTTOM,y
    rts


// player_dies
// Called when the player touches an enemy (the cell where it happened is in
// tempRow / tempCol).  Two animation phases, each with a falling sound:
//   1. the bug flips through four squashed frames ($2A-$2D), colours 2-5
//   2. a splat: dot $2E, ring $2F, big splat $00, then erased
// Then a life is lost.  If any are left the level is reset, otherwise the
// title screen is shown again.  (playerRow and playerCol are borrowed as
// working variables here; reset_level restores them.)
player_dies:
    lda  #$0F                     // volume 15
    sta  VIC_VOLUME
    ldx  #$02                     // X = colour 2 (steps 2,3,4,5)
    lda  #$E6                     // pitch $E6 ...
pd_spin:
    sta  VIC_ALTO                 // ... on the alto and bass voices
    sta  VIC_BASS
    sta  playerRow                // pitch kept in playerRow ...
    stx  playerCol                // ... colour kept in playerCol
    txa                           // character = colour + $28 = $2A..$2D
    clc
    adc  #$28
    sta  targetChar
    jsr  draw_cell                // draw it at tempRow, tempCol
    ldx  #$00                     // delay between frames: 60 x 255 loops
pd_wait_outer:
    ldy  #$00
pd_wait_inner:
    iny
    cpy  #$FF
    bne  pd_wait_inner
    inx
    cpx  #$3C
    bne  pd_wait_outer
    ldx  playerCol                // next colour: 2,3,4,5,2,...
    inx
    cpx  #$06
    bne  pd_colour_ok
    ldx  #$02
pd_colour_ok:
    lda  playerRow                // pitch - 5 ...
    sec
    sbc  #$05
    cmp  #$AA                     // ... until it reaches $AA
    beq  pd_splat
    jmp  pd_spin
pd_splat:
    lda  #$96                     // phase 2: starting pitch $96
pd_splat_loop:
    sta  VIC_SOPRANO              // soprano + alto
    sta  VIC_ALTO
    sta  playerRow
    cmp  #$B4                     // pitch < $B4: small dot ($2E)
    bpl  pd_not_small
    ldx  #$2E
    jmp  pd_got_char
pd_not_small:
    cmp  #$D2                     // pitch < $D2: ring ($2F)
    bpl  pd_not_ring
    ldx  #$2F
    jmp  pd_got_char
pd_not_ring:
    ldx  #$00                     // otherwise: splat (character $00)
pd_got_char:
    cmp  #$F0                     // pitch reached $F0: draw a space instead (erase)
    bne  pd_draw
    ldx  #$20
pd_draw:
    stx  targetChar               // draw it
    jsr  draw_cell
    ldx  #$00                     // delay: 20 x 255 loops
pd_splat_outer:
    ldy  #$00
pd_splat_inner:
    iny
    cpy  #$FF
    bne  pd_splat_inner
    inx
    cpx  #$14
    bne  pd_splat_outer
    lda  playerRow                // pitch + 10 ...
    clc
    adc  #$0A
    cmp  #$FA                     // ... until $FA
    bne  pd_splat_loop
    lda  #$00                     // silence all five voice registers ($900A-$900E)
    ldx  #$00
pd_silence:
    sta  VIC_BASS,x
    inx
    cpx  #$05
    bne  pd_silence
    ldx  lives                    // lives - 1
    dex
    stx  lives
    txa                           // refresh the lives digit
    clc
    adc  #$30
    sta  $1E2E
    cpx  #$00                     // any lives left?
    beq  pd_game_over
    jmp  reset_level              // yes: reset the level and carry on
pd_game_over:
    jmp  game_over                // no: game over

// draw_cell
// Draws character targetChar in colour playerCol at screen position
// (tempRow, tempCol).  Only used by the death animation, which borrows
// playerCol to hold the colour.
draw_cell:
    lda  tempRow                  // Y = rowOffset[tempRow] + tempCol
    tay
    lda  rowOffset,y
    clc
    adc  tempCol
    tay
    lda  tempRow
    cmp  #$0A                     // rows 0-9 are in the top half ...
    bpl  dc_lower
    lda  targetChar               // character and colour into the top half
    sta  MAZE_TOP,y
    lda  playerCol
    sta  MAZE_TOP_COL,y
    rts
dc_lower:
    lda  targetChar               // ... rows 10-19 in the bottom half
    sta  MAZE_BOTTOM,y
    lda  playerCol
    sta  MAZE_BOTTOM_COL,y
    rts

// move_enemies
// Moves every enemy (numbers 2 .. enemyLimit) by one cell.  For each one:
//   a. look at the cell it is standing on; if the bomb cloud is there it dies,
//      if the player is there the player dies
//   b. otherwise put back the dot / blank that it was covering
//   c. choose a direction: chase the player vertically, else chase horizontally,
//      else keep going the same way, else wander (cycling 2,3,4,5)
//   d. move it, remember what is in the new cell, and draw the enemy there in red
// Direction codes: 2 = left, 3 = down, 4 = up, 5 = right.
move_enemies:
    ldx  enemyFrame               // enemy animation frame cycles $27, $28
    inx
    cpx  #$29
    bne  me_frame_ok
    ldx  #$27
me_frame_ok:
    stx  enemyFrame
    ldx  #$01                     // enemy counter (incremented first, so enemies run from 2)
me_next_enemy:
    inx
    lda  enemyRow,x               // Y = rowOffset[row] + column for this enemy ...
    tay
    lda  rowOffset,y
    clc
    adc  enemyCol,x
    tay
    lda  enemyRow,x
    cmp  #$0A
    bpl  me_lower
    lda  MAZE_TOP,y               // ... read the cell it is standing on (top half) ...
    jmp  me_got_char
me_lower:
    lda  MAZE_BOTTOM,y            // ... or bottom half
me_got_char:
    cmp  #$20                     // cell holds a door piece (< $20): skip the restore step
    bpl  me_check_under
    jmp  me_chase_row
me_check_under:
    lda  enemyUnder,x             // what the enemy was standing on
    cmp  #$29                     // $29 = the bomb cloud
    bne  me_check_player
    jsr  kill_enemy               // killed: score, respawn
me_check_player:
    cmp  #$23                     // $23-$26 = the player is in this cell
    bmi  me_restore_under
    cmp  #$27
    bpl  me_restore_under
    lda  playerRow                // caught the player: tempRow/tempCol = player position
    sta  tempRow
    lda  playerCol
    sta  tempCol
    jmp  player_dies              // -> player_dies
me_restore_under:
    cmp  #$27                     // put back the dot / blank under the enemy (unless it was another enemy)
    bpl  me_chase_row
    lda  enemyRow,x
    tay
    lda  rowOffset,y
    clc
    adc  enemyCol,x
    tay
    lda  enemyRow,x
    cmp  #$0A
    bpl  me_restore_lower
    lda  enemyUnder,x
    sta  MAZE_TOP,y
    lda  #$07
    sta  MAZE_TOP_COL,y
    jmp  me_chase_row
me_restore_lower:
    lda  enemyUnder,x
    sta  MAZE_BOTTOM,y
    lda  #$07
    sta  MAZE_BOTTOM_COL,y
me_chase_row:
    lda  enemyRow,x               // CHASE: compare enemy row with player row
    cmp  playerRow
    beq  me_chase_col
    bmi  me_row_less
    ldy  #$04                     // enemy below the player: try up (4)
    jsr  try_move
    jmp  me_row_tried
me_row_less:
    ldy  #$03                     // enemy above the player: try down (3)
    jsr  try_move
me_row_tried:
    lda  tempRow                  // tempRow = 1 if the move is possible
    cmp  #$01
    bne  me_chase_col
    jmp  me_commit                // it worked: take it
me_chase_col:
    lda  enemyCol,x               // CHASE: compare enemy column with player column
    cmp  playerCol
    beq  me_keep_dir
    bmi  me_col_less
    ldy  #$02                     // enemy to the right of the player: try left (2)
    jsr  try_move
    jmp  me_col_tried
me_col_less:
    ldy  #$05                     // enemy to the left of the player: try right (5)
    jsr  try_move
me_col_tried:
    lda  tempRow
    cmp  #$01
    bne  me_keep_dir
    jmp  me_commit
me_keep_dir:
    lda  enemyDir,x               // blocked: carry on in the current direction
    tay
    jsr  try_move
    lda  tempRow
    cmp  #$01
    bne  me_wander
    jmp  me_commit
me_wander:
    ldy  wanderDir                // still blocked: WANDER - cycle through directions 2,3,4,5 until one works
    iny
    cpy  #$06
    bne  me_wander_ok
    ldy  #$02
me_wander_ok:
    sty  wanderDir
    jsr  try_move
    lda  tempRow
    cmp  #$01
    bne  me_wander_again
    jmp  me_commit
me_wander_again:
    jmp  me_wander

// MOVE the enemy.  Y = chosen direction.
me_commit:
    tya                           // remember the direction
    sta  enemyDir,x
    tay
    cpy  #$04
    bne  mc_not_up
    lda  enemyRow,x               // 4 = up: row - 1
    sec
    sbc  #$01
    sta  enemyRow,x
    jmp  mc_draw
mc_not_up:
    cpy  #$03                     // 3 = down: row + 1
    bne  mc_not_down
    lda  enemyRow,x
    clc
    adc  #$01
    sta  enemyRow,x
    jmp  mc_draw
mc_not_down:
    cpy  #$02                     // 2 = left: column - 1, wrapping from 0 round to 21 (side tunnel)
    bne  mc_right
    lda  enemyCol,x
    sec
    sbc  #$01
    cmp  #$FF
    bne  mc_left_store
    lda  #$15
mc_left_store:
    sta  enemyCol,x
    jmp  mc_draw
mc_right:
    lda  enemyCol,x               // 5 = right: column + 1, wrapping from 21 round to 0
    clc
    adc  #$01
    cmp  #$16
    bne  mc_right_store
    lda  #$00
mc_right_store:
    sta  enemyCol,x

// Remember what is in the new cell (enemyUnder) and draw the enemy there in red
mc_draw:
    lda  enemyRow,x
    tay
    lda  rowOffset,y
    clc
    adc  enemyCol,x
    tay
    lda  enemyRow,x
    cmp  #$0A
    bpl  mc_draw_lower
    lda  MAZE_TOP,y               // read the cell
    sta  enemyUnder,x
    lda  enemyFrame               // enemy animation frame
    sta  MAZE_TOP,y
    lda  #$02                     // colour 2 = red
    sta  MAZE_TOP_COL,y
    jmp  mc_next
mc_draw_lower:
    lda  MAZE_BOTTOM,y
    sta  enemyUnder,x
    lda  enemyFrame
    sta  MAZE_BOTTOM,y
    lda  #$02
    sta  MAZE_BOTTOM_COL,y
mc_next:
    cpx  enemyLimit               // last enemy done?
    beq  mc_done
    jmp  me_next_enemy
mc_done:
    rts

// try_move   (X = enemy number, Y = direction to try)
// Returns tempRow = 1 if the enemy may step that way, 0 if blocked.
// A move is refused if it reverses the enemy's current direction (opposite
// directions add up to 7).  A cell is free if its character is >= $20 and
// is not a wall ($21).  Side-effect: the enemy's column is pre-adjusted so
// that the tunnel wrap-around arithmetic works (22 for 'left of 0', $FF for
// 'right of 21').
try_move:
    tya                           // new direction + current direction ...
    clc
    adc  enemyDir,x
    cmp  #$07                     // ... = 7 means opposite: refuse
    bne  tm_not_reverse
    jmp  tm_blocked
tm_not_reverse:
    lda  enemyCol,x               // left from column 0: use 22 so that 22 - 1 = 21 ...
    cpy  #$02
    bne  tm_chk_right
    cmp  #$00
    bne  tm_chk_right
    lda  #$16
tm_chk_right:
    cpy  #$05                     // right from column 21: use $FF so that $FF + 1 = 0
    bne  tm_col_store
    cmp  #$15
    bne  tm_col_store
    lda  #$FF
tm_col_store:
    sta  enemyCol,x               // Y = rowOffset[row] + column ...
    clc
    lda  enemyRow,x
    sty  tempCol
    tay
    lda  rowOffset,y
    clc
    adc  enemyCol,x
    ldy  tempCol
    cpy  #$04                     // ... then step one cell in the chosen direction:
    bne  tm_not_up
    sec                           // up: -22
    sbc  #$16
    jmp  tm_fetch
tm_not_up:
    cpy  #$05                     // right: +1
    bne  tm_not_right
    clc
    adc  #$01
    jmp  tm_fetch
tm_not_right:
    cpy  #$03                     // down: +22
    bne  tm_left
    clc
    adc  #$16
    jmp  tm_fetch
tm_left:
    sec                           // left: -1
    sbc  #$01
tm_fetch:
    sty  tempCol                  // fetch the character in that cell (top / bottom half)
    tay
    lda  enemyRow,x
    cmp  #$0A
    bpl  tm_fetch_lower
    lda  MAZE_TOP,y
    jmp  tm_check_cell
tm_fetch_lower:
    lda  MAZE_BOTTOM,y
tm_check_cell:
    cmp  #$20                     // characters below $20 (door pieces) and the wall ($21) block the way
    bmi  tm_blocked
    cmp  #$21
    beq  tm_blocked
    ldy  #$01                     // free
    jmp  tm_done
tm_blocked:
    ldy  #$00                     // blocked
tm_done:
    sty  tempRow                  // result in tempRow
    ldy  tempCol                  // tempCol holds the direction that was tried
    rts

// player_update
// The player's turn: draw/clear the bug's cell, read the joystick, work out the
// destination, deal with whatever is there (wall, dot, door, enemy), and move.
player_update:
    ldx  playerFrame              // player animation frame cycles $23,$24,$25,$26
    inx
    cpx  #$27
    bne  pu_frame_ok
    ldx  #$23
pu_frame_ok:
    stx  playerFrame
    ldx  playerRow                // Y = rowOffset[playerRow] + playerCol
    lda  rowOffset,x
    clc
    adc  playerCol
    tay
    lda  fireFlag                 // fireFlag = $FF: the bomb was fired on the previous move
    cmp  #$FF
    bne  pu_blank

// Bomb just fired: wait here until FIRE is released (value >= $5F), then show the
// cloud ($29) where the bug stands.  Otherwise just blank the cell it is leaving.
pu_wait_release:
    ReadJoystick()               // loop while FIRE is held
    cmp  #$5F
    bmi  pu_wait_release
    lda  #$29                     // $29 = cloud
    bne  pu_draw
pu_blank:
    lda  #$20                     // $20 = space
pu_draw:
    cpx  #$0A                     // store it in the top half ...
    bpl  pu_draw_lower
    sta  MAZE_TOP,y
    jmp  pu_check_spray
pu_draw_lower:
    sta  MAZE_BOTTOM,y            // ... or the bottom half

// If the cloud was drawn, play the bomb sound: volume 15 falling to 0,
// soprano pitch $BE falling in steps of 4, with a short wait between steps
pu_check_spray:
    cmp  #$29                     // was a cloud drawn?
    bne  pu_read_joy
    ldx  #$0F                     // volume 15 ...
    lda  #$BE                     // ... pitch $BE
pu_spray_sweep:
    stx  VIC_VOLUME
    sta  VIC_SOPRANO
    sec
    sbc  #$04
    dex
    ldy  #$00
pu_spray_outer:
    sty  tempRow
    ldy  #$00
pu_spray_inner:
    iny
    cpy  #$00
    bne  pu_spray_inner
    ldy  tempRow
    iny
    cpy  #$0A
    bne  pu_spray_outer
    cpx  #$FF
    bne  pu_spray_sweep
    inx                           // volume 0
    stx  VIC_SOPRANO

// READ THE JOYSTICK.  A new destination is built in tempRow (Y after vertical
// movement) and Y (column); A becomes $FF if FIRE was held with up/down/left.
// Port values (after ORA #$40):  $7A up  $76 down  $6E left   (add fire: $5A $56 $4E)
pu_read_joy:
    ReadJoystick()               // VIA1 port A
    tax                           // X = joystick bits
    lda  #$00                     // A = 0 (no bomb)
    ldy  playerRow                // Y = player row
    cpx  #$7A                     // up?
    beq  pu_up
    cpx  #$5A                     // up + fire?
    bne  pu_test_down
    lda  #$FF                     // fire: A = $FF
pu_up:
    dey                           // row - 1 ...
    cpy  #$FF
    bne  pu_test_down
    ldy  #$00                     // ... but not off the top of the maze
pu_test_down:
    cpx  #$76                     // down?
    beq  pu_down
    cpx  #$56                     // down + fire?
    beq  pu_down_fire
    jmp  pu_vert_done
pu_down_fire:
    lda  #$FF                     // fire: A = $FF
pu_down:
    iny                           // row + 1 ...
    cpy  #$14                     // ... but not beyond row 19
    bne  pu_vert_done
    dey
pu_vert_done:
    sty  tempRow                  // destination row
    ldy  playerCol                // Y = player column
    cpx  #$6E                     // left?
    beq  pu_left
    cpx  #$4E                     // left + fire?
    beq  pu_left_fire
    jmp  pu_test_right
pu_left_fire:
    lda  #$FF                     // fire: A = $FF
pu_left:
    dey                           // column - 1 ...
    cpy  #$FF
    bne  pu_test_right
    ldy  #$15                     // ... wrapping from 0 round to 21
pu_test_right:
    cpx  #$5E                     // fire alone ($5E) or idle ($7E): look for RIGHT on VIA2 port B bit 7
    beq  pu_right_read
    cpx  #$7E
    beq  pu_right_read
    jmp  pu_store_move
pu_right_read:
    bit  VIA2_PORTB               // FIX: bit 7 = joystick RIGHT (0 = pressed); BIT leaves A (the fire flag) alone
    bmi  pu_store_move            // (the original compared the whole port with $77, which depends on the keyboard-scan latch)
    iny                           // column + 1 ...
    cpy  #$16
    bne  pu_store_move
    ldy  #$00                     // ... wrapping from 21 round to 0
pu_store_move:
    sty  tempCol                  // destination column
    sta  fireFlag                 // A is $FF only when FIRE was pressed with a direction

// Bomb requested?  It needs a bomb in stock; using one decrements 'bombs'.
pu_fire_check:
    cmp  #$FF                     // fire requested?
    bne  pu_lookup
    ldx  bombs                    // out of bombs?
    cpx  #$00
    bne  pu_use_bomb
    lda  #$00                     // yes: no bomb after all
    jmp  pu_lookup
pu_use_bomb:
    dex                           // one bomb used
    stx  bombs

// Look at the destination cell (top half if row < 10, else bottom half)
pu_lookup:
    sta  fireFlag                 // store the fire flag (also stops a stale $FF)
    ldx  tempRow                  // Y = rowOffset[tempRow] + tempCol
    lda  rowOffset,x
    clc
    adc  tempCol
    tay
    cpx  #$0A
    bpl  pu_lookup_lower
    lda  MAZE_TOP,y               // targetChar = what is there
    sta  targetChar
    jmp  pu_examine

// Free move: draw the bug (playerFrame) in blue (6) at the destination ...
pu_place_upper:
    lda  playerFrame              // top half
    sta  MAZE_TOP,y
    lda  #$06
    sta  MAZE_TOP_COL,y
    jmp  pu_commit
pu_lookup_lower:
    lda  MAZE_BOTTOM,y
    sta  targetChar
    jmp  pu_examine
pu_place_lower:
    lda  playerFrame              // bottom half
    sta  MAZE_BOTTOM,y
    lda  #$06
    sta  MAZE_BOTTOM_COL,y
pu_commit:
    lda  tempRow                  // ... and make the destination the new player position
    sta  playerRow
    lda  tempCol
    sta  playerCol
    rts

// Decide what to do about the destination character:
pu_examine:
    lda  targetChar               // wall ($21) ...
    cmp  #$21
    bne  pu_not_wall
pu_blocked:
    lda  playerRow                // blocked: stay put and run the move test again
    sta  tempRow
    lda  playerCol
    sta  tempCol
    jmp  pu_fire_check
pu_not_wall:
    cmp  #$1F                     // ... or door hub ($1F) block the bug
    beq  pu_blocked
    cmp  #$22                     // $22 = dot: eat it
    bne  pu_not_enemy
    jmp  pu_eat_dot
pu_not_enemy:
    cmp  #$27                     // $27 and above = an enemy: the bug dies
    bmi  pu_door_upper
    jmp  player_dies

// Revolving doors.  A door is a hub ($1F) with two opposite arms:
//       $1B $1F $1C    (horizontal)          $1D   (above the hub)
//                                            $1F
//                                            $1E   (below the hub)
// Walking into an arm puts the bug in that arm's cell and swings the door
// through 90 degrees: the opposite arm is removed and two arms appear on the
// other axis.  There are eight cases (4 arms x top / bottom half of the maze,
// because the halves sit at different addresses, so the offsets differ).
// Colour 6 (blue) is set for each new arm.
pu_door_upper:
    cpx  #$0A                     // top half? (row < 10)
    bpl  pu_door_lower
    cmp  #$1B                     // pushed the left arm $1B: remove right arm, add arms above and below the hub
    bne  du_1c
    lda  #$20
    sta  $1E44,y
    lda  #$1D
    sta  $1E2D,y
    lda  #$1E
    sta  $1E59,y
    lda  #$06
    sta  $962D,y
    sta  $9659,y
du_1c:
    cmp  #$1C                     // pushed the right arm $1C: remove left arm, add arms above and below the hub
    bne  du_1d
    lda  #$20
    sta  $1E40,y
    lda  #$1D
    sta  $1E2B,y
    lda  #$1E
    sta  $1E57,y
    lda  #$06
    sta  $962B,y
    sta  $9657,y
du_1d:
    cmp  #$1D                     // pushed the top arm $1D: remove bottom arm, add arms left and right of the hub
    bne  du_1e
    lda  #$20
    sta  $1E6E,y
    lda  #$1B
    sta  $1E57,y
    lda  #$1C
    sta  $1E59,y
    lda  #$06
    sta  $9657,y
    sta  $9659,y
du_1e:
    cmp  #$1E                     // pushed the bottom arm $1E: remove top arm, add arms left and right of the hub
    beq  du_1e_do
    jmp  pu_after_door
du_1e_do:
    lda  #$20
    sta  $1E16,y
    lda  #$1B
    sta  $1E2B,y
    lda  #$1C
    sta  $1E2D,y
    lda  #$06
    sta  $962B,y
    sta  $962D,y

// (same four cases for the bottom half of the maze)
pu_door_lower:
    cmp  #$1B                     // left arm
    bne  dl_1c
    lda  #$20
    sta  $1F20,y
    lda  #$1D
    sta  $1F09,y
    lda  #$1E
    sta  $1F35,y
    lda  #$06
    sta  $9709,y
    sta  $9735,y
dl_1c:
    cmp  #$1C                     // right arm
    bne  dl_1d
    lda  #$20
    sta  $1F1C,y
    lda  #$1D
    sta  $1F07,y
    lda  #$1E
    sta  $1F33,y
    lda  #$06
    sta  $9707,y
    sta  $9733,y
dl_1d:
    cmp  #$1D                     // top arm
    bne  dl_1e
    lda  #$20
    sta  $1F4A,y
    lda  #$1B
    sta  $1F33,y
    lda  #$1C
    sta  $1F35,y
    lda  #$06
    sta  $9733,y
    sta  $9735,y
dl_1e:
    cmp  #$1E                     // bottom arm
    bne  pu_after_door
    lda  #$20
    sta  $1EF2,y
    lda  #$1B
    sta  $1F07,y
    lda  #$1C
    sta  $1F09,y
    lda  #$06
    sta  $9707,y
    sta  $9709,y
pu_after_door:
    lda  targetChar               // was it a door arm ($1B-$1E)?  Then make a clicking sound
    cmp  #$1F
    bpl  pu_choose_half
    lda  #$0F                     // volume 15, alto and soprano $96
    sta  VIC_VOLUME
    lda  #$96
    sta  VIC_ALTO
    sta  VIC_SOPRANO
pu_choose_half:
    lda  tempRow                  // draw the bug at its new position, in the correct half of the maze
    cmp  #$0A
    bpl  pu_goto_lower
    jmp  pu_place_upper
pu_goto_lower:
    jmp  pu_place_lower

// pu_eat_dot
// Eating a dot is worth 'enemyLimit' points (2-6), so playing against more
// enemies scores faster.  The 209th dot ($D1) ends the level.
pu_eat_dot:
    lda  enemyLimit               // score units digit += enemyLimit
    clc
    adc  score+5
    sta  score+5
    jsr  update_score             // carry and redraw
    lda  #$0A                     // short blip: volume 10, soprano $A0
    sta  VIC_VOLUME
    lda  #$A0
    sta  VIC_SOPRANO
    ldx  dotsEaten                // count the dots eaten
    inx
    stx  dotsEaten
    cpx  dotTarget                // all the dots of this maze?
    beq  pu_level_done
    jmp  pu_after_door            // no: carry on and move the bug
pu_level_done:
    jmp  level_complete           // yes: level complete


// update_score
// The score is six ASCII digits starting at 'score'.  Adding to a digit can
// leave it above '9'; this routine does the decimal carry from the right,
// prints the score on row 1, compares it with the hi-score (most significant
// digit first), copies it over if it is higher, and prints the hi-score too.
// (A carry out of the top digit spills into 'lives' - an extra life every
// 1,000,000 points.)
update_score:
    ldx  #$05                     // start at the units digit (index 5)
us_carry_loop:
    lda  score,x
    cmp  #$3A                     // digit above '9' ($3A)?
    bmi  us_next_digit
    sec                           // subtract 10 ...
    sbc  #$0A
    sta  score,x
    lda  lives,x                  // ... and add one to the digit on its left
    clc
    adc  #$01
    sta  lives,x
us_next_digit:
    dex
    cpx  #$FF
    bne  us_carry_loop
    ldx  #$00                     // print the score at row 1, col 0
us_show:
    lda  score,x
    sta  $1E16,x
    inx
    cpx  #$06
    bne  us_show
    ldx  #$00                     // compare with the hi-score, left to right
us_cmp_hi:
    lda  score,x
    cmp  hiScore,x
    beq  us_cmp_next              // equal so far: look at the next digit
    bmi  us_show_hi               // lower: nothing to do
    jmp  us_new_hi                // higher: new hi-score
us_cmp_next:
    inx
    cpx  #$06
    bne  us_cmp_hi
    jmp  us_show_hi
us_new_hi:
    ldx  #$00                     // copy score -> hiScore
us_copy_hi:
    lda  score,x
    sta  hiScore,x
    inx
    cpx  #$06
    bne  us_copy_hi
us_show_hi:
    ldx  #$00                     // print the hi-score at row 1, col 15
us_show_hi_loop:
    lda  hiScore,x
    sta  $1E25,x
    inx
    cpx  #$06
    bne  us_show_hi_loop
    rts


// show_level
// Prints the two level digits at the right-hand end of row 2.
show_level:
    lda  levelTens
    sta  $1E40
    lda  levelUnits
    sta  $1E41
    rts

// game_over
// All lives are gone.  Print GAME OVER over the maze (row 12, column 6, red),
// play a falling tune, wait for FIRE to be released (so a player who is still
// pressing it does not start a new game by accident) and go to the title screen.
game_over:
    ldx  #$08
go_text:
    lda  txtGameOver,x
    sta  $1F0E,x                  // screen row 12, column 6 onwards
    lda  #$02
    sta  $970E,x                  // red
    dex
    bpl  go_text
    lda  #$00
    sta  tuneSkip                 // cannot be skipped
    ldx  #tuneGameOver-tuneData
    jsr  play_tune
go_release:
    lda  VIA1_PORTA
    and  #$20                     // bit 5 = FIRE (0 = pressed)
    beq  go_release
    jmp  title_screen

// play_tune
// Plays a tune from tuneData on the soprano voice.  X = offset of the tune.
// A tune is a list of (pitch, length) byte pairs ended by a 0 pitch.
//   pitch $80-$FF  a note (see the table of note names at tuneData)
//   pitch 1        a rest
//   length         in units of about 28 ms
// If tuneSkip is $20 the tune stops as soon as FIRE (bit 5 of the joystick port) is pressed.
play_tune:
    stx  tuneIndex
    lda  #$0F
    sta  VIC_VOLUME               // full volume
pt_note:
    ldx  tuneIndex
    lda  tuneData,x
    beq  pt_done                  // 0 = end of the tune
    sta  VIC_SOPRANO
    lda  tuneData+1,x
    sta  tuneDur
    inx
    inx
    stx  tuneIndex
pt_wait:
    ldx  #$18                     // one length unit: 24 x 256 passes of a tiny loop = ~28 ms
pt_x:
    ldy  #$00
pt_y:
    iny
    bne  pt_y
    dex
    bne  pt_x
    dec  tuneDur
    bne  pt_wait
    lda  VIA1_PORTA
    eor  #$FF
    and  tuneSkip
    beq  pt_note                  // not skipping, or fire not pressed: next note
pt_done:
    lda  #$00
    sta  VIC_SOPRANO              // silence
    sta  VIC_VOLUME
    rts

// draw_maze
// Builds the maze on the screen and in colour RAM.  The maze is not stored as a
// picture: only the WALLS are stored, as a bitmap (1 bit per cell, see
// wallBitsTop / wallBitsBottom).  Everything else follows from simple rules:
//   - a cell that is not a wall is a dot
//   - the six revolving doors are listed in doorTable
//   - the cells above and below each door hub are blank, and so is the
//     cell where killed enemies respawn (row 9, column 10)
// Pass 1 fills both halves of the maze (220 cells each) from the bitmaps:
//   wall = character $21, colour 4 (purple)     dot = character $22, colour 7 (yellow)
// Pass 2 blanks the respawn cell and draws the doors (patch_doors).
draw_maze:
    ldx  mazeNumber               // which maze? 0 = maze 1, 1 = maze 2
    lda  wallOffsetTable,x
    sta  wallBase                 // where its wall bitmaps start in wallBits
    lda  doorOffsetTable,x
    sta  doorBase                 // where its doors start in doorTable
    lda  dotTotalTable,x
    sta  dotTarget                // how many dots end this level
    ldx  #$00                     // X = cell number 0-219 (same in both halves)
dm_loop:
    txa
    and  #$07
    bne  dm_cells                 // every 8th cell: load the next byte of each bitmap
    txa
    lsr
    lsr
    lsr
    clc
    adc  wallBase
    tay                           // Y = X / 8 + start of this maze's bitmaps
    lda  wallBits,y               // top half ...
    sta  shiftTop
    tya
    clc
    adc  #28
    tay
    lda  wallBits,y               // ... and bottom half (28 bytes further on)
    sta  shiftBottom
dm_cells:
    ldy  #$07                     // default: dot, yellow
    lda  #$22
    asl  shiftTop                 // next bit (top half) into carry: 1 = wall
    bcc  dm_top
    ldy  #$04                     // wall, purple
    lda  #$21
dm_top:
    sta  MAZE_TOP,x
    tya
    sta  MAZE_TOP_COL,x
    ldy  #$07
    lda  #$22
    asl  shiftBottom              // same for the bottom half
    bcc  dm_bottom
    ldy  #$04
    lda  #$21
dm_bottom:
    sta  MAZE_BOTTOM,x
    tya
    sta  MAZE_BOTTOM_COL,x
    inx
    cpx  #$DC                     // 220 cells done?
    bne  dm_loop
    lda  #$20
    sta  MAZE_TOP+9*22+10         // the respawn cell (row 9, column 10) is blank
    sta  MAZE_BOTTOM+4*22+10      // and so is the player's start cell (row 14, column 10)
    lda  #$0A
    sta  doorCount                // fall into patch_doors for the 6 doors, last to first

// patch_doors
// For each door in doorTable (a screen address = the cell ABOVE the hub) draw
// the five cells that make up a door and its surroundings:
//   +0  blank above the hub        +21 left arm  $1B     +22 hub $1F
//   +23 right arm  $1C             +44 blank below the hub
// The arms and hub are blue (6); the two blanks are yellow (7).
// A pair of zero-page pointers is used: screenPtr -> screen, colourPtr -> colour RAM
// (the colour RAM address is the screen address + $7800).
patch_doors:
    lda  doorCount
    clc
    adc  doorBase                 // doorBase = 0 for maze 1, 12 for maze 2 (6 doors x 2 bytes each)
    tax
    lda  doorTable,x
    sta  screenPtr
    sta  colourPtr
    lda  doorTable+1,x
    sta  screenPtr+1
    clc
    adc  #$78
    sta  colourPtr+1
    ldx  #$04
pd_cell:
    ldy  cellOffset,x
    lda  cellChar,x
    sta  (screenPtr),y
    lda  cellColour,x
    sta  (colourPtr),y
    dex
    bpl  pd_cell
    dec  doorCount
    dec  doorCount
    bpl  patch_doors
    rts

// ======================================================================
// GAME VARIABLES  ($1A22-$1A47)  (the values below are the load-time contents)
//
// Enemy tables are indexed by enemy number X = 2..6 (enemy 'n' of a game with
// enemyLimit = n+1).  Table entries 0 and 1 are never used by the game, which
// is why reset_level can initialise them with loops that start at X = 0.
// ======================================================================
pollLimit:   .byte $28            // title screen: key-poll delay (outer loop count), see ts_check_fire
enemyDir:    .byte $05,$05,$03,$02,$02   // $1A23  direction: 2=left 3=down 4=up 5=right  (indexed from enemy 2: $1A25...)
enemyUnder:  .byte $02,$03,$22,$22,$22,$22   // $1A28  char each enemy is standing on (dot / blank) (indexed from enemy 2: $1A2A...)
enemyCol:    .byte $22,$F7,$06,$01,$14,$14   // $1A2E  column 0-21 (indexed from enemy 2: $1A30...)
             //   $1A2F doubles as 'fireFlag': $FF = bomb fired on the previous move
enemyRow:    .byte $14,$01,$0C,$12,$01,$07,$12   // $1A34  row 0-19 (indexed from enemy 2: $1A36...)
lives:       .byte $05            // $1A3B  lives left (and the 'carry' slot above the score)
score:       .text "000000"       // $1A3C  six ASCII digits
hiScore:     .text "000000"       // $1A42  six ASCII digits

// ======================================================================
// THE MAZE  (20 rows of 22 columns)
//
// The picture below is the maze as designed.  Only the '#' walls are actually
// used by the assembler: they are packed into a bitmap (wallBitsTop for rows
// 0-9, wallBitsBottom for rows 10-19, 28 bytes each, 1 bit per cell, first
// cell in bit 7 of the first byte).  draw_maze rebuilds the rest:
//
//   #  wall ($21)       .  dot ($22)       (space) blank ($20)
//   < + >  horizontal revolving door ($1B arm, $1F hub, $1C arm)
//
// Dots fill every non-wall cell; blanks sit above and below each door hub (so
// the door can swing round to the vertical) and at the respawn cell (row 9,
// column 10); the doors are listed in doorTable.  If you edit the picture,
// edit those to match.  The left and right edges wrap round: the player and the
// enemies can leave through the gaps in row 9 and appear on the other side.
// ======================================================================
// ---- Maze 1 (the original maze)
.var mazeRows1 = List()
.eval mazeRows1.add("######################")   // row 0
.eval mazeRows1.add("#....................#")   // row 1
.eval mazeRows1.add("#.###.##.#.###.#.###.#")   // row 2
.eval mazeRows1.add("#... .#.... ...#. ...#")   // row 3
.eval mazeRows1.add("#.#<+>#.##<+>#.#<+>#.#")   // row 4
.eval mazeRows1.add("#.#. ....#. ..... .#.#")   // row 5
.eval mazeRows1.add("#.#.####.#.###.###.#.#")   // row 6
.eval mazeRows1.add("#.....#......#.#.....#")   // row 7
.eval mazeRows1.add("#####.#.####.#.#.#####")   // row 8
.eval mazeRows1.add(".......... ...........")   // row 9
.eval mazeRows1.add("##.###.###.###.####.##")   // row 10
.eval mazeRows1.add("#..#.....#.#......#..#")   // row 11
.eval mazeRows1.add("#.##.#.#.....#.##.##.#")   // row 12
.eval mazeRows1.add("#.##.#.#.###.#.##.##.#")   // row 13
.eval mazeRows1.add("#.. .#.... .....#. ..#")   // row 14
.eval mazeRows1.add("##<+>##.#<+>#.#.#<+>##")   // row 15
.eval mazeRows1.add("#.. ....#. ...#... ..#")   // row 16
.eval mazeRows1.add("#.#####.#.###.#.####.#")   // row 17
.eval mazeRows1.add("#....................#")   // row 18
.eval mazeRows1.add("######################")   // row 19

// ---- Maze 2 (new).  Rules any maze must follow (all three do):
//   - 22 x 20 cells; wall all round except the row-9 tunnel at columns 0 and 21
//   - all non-door cells form ONE connected region, and every such cell has at
//     least two open neighbours (the enemy AI cannot turn round, so a dead end
//     would make it loop forever)
//   - ROW 9 MUST BE COMPLETELY OPEN: enemies stepping up from row 10 read
//     unmapped memory (no RAM at $2000), which only works because that reads as
//     "blank"; with row 9 open it is always correct
//   - a swinging door must never leave a dead end: with ANY door turned to the
//     vertical position (arms above and below the hub), every open cell must
//     still have two open neighbours.  So the cell above the 'above-hub' cell
//     and below the 'below-hub' cell must not be a one-wide stub
//   - exactly six doors: each a 3x3 open block whose middle row is
//     wall,'<','+','>',wall; the cells above and below the hub are blank
//   - blank at the respawn cell (row 9, column 10) and the player's start cell
//     (row 14, column 10); dots at the enemy start cells (rows/columns
//     7/1, 18/1, 1/20, 7/20, 18/20)
//   - the dot count is taken from the picture: every '.' is a dot
.var mazeRows2 = List()
.eval mazeRows2.add("######################")   // row 0
.eval mazeRows2.add("#....................#")   // row 1
.eval mazeRows2.add("#.####.##.##.##.####.#")   // row 2
.eval mazeRows2.add("#... ..##....##.. ...#")   // row 3
.eval mazeRows2.add("#.#<+>##..##..##<+>#.#")   // row 4
.eval mazeRows2.add("#... ..#.####.#.. ...#")   // row 5
.eval mazeRows2.add("#.####...#..#...####.#")   // row 6
.eval mazeRows2.add("#....#.#......#.#....#")   // row 7
.eval mazeRows2.add("##.#.#.##.##.##.#.#.##")   // row 8
.eval mazeRows2.add(".......... ...........")   // row 9
.eval mazeRows2.add("###.#.##########.#.###")   // row 10
.eval mazeRows2.add("#...... ...... ......#")   // row 11
.eval mazeRows2.add("#...##<+>####<+>##...#")   // row 12
.eval mazeRows2.add("##.##.. ..##.. ..##.##")   // row 13
.eval mazeRows2.add("#... ..##. ..##.. ...#")   // row 14
.eval mazeRows2.add("#.#<+>#...##...#<+>#.#")   // row 15
.eval mazeRows2.add("#... ...######... ...#")   // row 16
.eval mazeRows2.add("#.###.#.#....#.#.###.#")   // row 17
.eval mazeRows2.add("#.........##.........#")   // row 18
.eval mazeRows2.add("######################")   // row 19

// ---- Maze 3 (follows the same rules as maze 2)
.var mazeRows3 = List()
.eval mazeRows3.add("######################")   // row 0
.eval mazeRows3.add("#...###........###...#")   // row 1
.eval mazeRows3.add("#.#.. ..#.##.#.. ..#.#")   // row 2
.eval mazeRows3.add("#.##<+>##.##.##<+>##.#")   // row 3
.eval mazeRows3.add("#.#.. .......... ..#.#")   // row 4
.eval mazeRows3.add("#.#.#####.##.#####.#.#")   // row 5
.eval mazeRows3.add("#.........##.........#")   // row 6
.eval mazeRows3.add("#.#.##.##....##.##.#.#")   // row 7
.eval mazeRows3.add("#.#.##.########.##.#.#")   // row 8
.eval mazeRows3.add(".......... ...........")   // row 9
.eval mazeRows3.add("#.###.###.##.###.###.#")   // row 10
.eval mazeRows3.add("#.. ...##....##... ..#")   // row 11
.eval mazeRows3.add("##<+>#..######..#<+>##")   // row 12
.eval mazeRows3.add("#.. ..#........#.. ..#")   // row 13
.eval mazeRows3.add("#.###.#### .####.###.#")   // row 14
.eval mazeRows3.add("#.#..... .... .....#.#")   // row 15
.eval mazeRows3.add("#.#.#.#<+>##<+>#.#.#.#")   // row 16
.eval mazeRows3.add("#.#..... .... .....#.#")   // row 17
.eval mazeRows3.add("#...##..######..##...#")   // row 18
.eval mazeRows3.add("######################")   // row 19

.macro WallBits(rows, firstRow) {
    .for (var b = 0; b < 28; b++) {
        .var v = 0
        .for (var k = 0; k < 8; k++) {
            .var n = b*8 + k
            .var bit = 0
            .if (n < 220) {
                .if (rows.get(firstRow + floor(n/22)).charAt(mod(n,22)) == '#') .eval bit = 1
            }
            .eval v = v*2 + bit
        }
        .byte v
    }
}

// Wall bitmaps: maze 1 top, maze 1 bottom, maze 2 top, maze 2 bottom (28 bytes each).
// draw_maze adds wallOffsetTable[maze] (0 or 56) to find the right pair.
wallBits:
    WallBits(mazeRows1, 0)
    WallBits(mazeRows1, 10)
    WallBits(mazeRows2, 0)
    WallBits(mazeRows2, 10)
    WallBits(mazeRows3, 0)
    WallBits(mazeRows3, 10)

// Doors: the assembler finds every '+' (door hub) in a picture and stores the
// screen address of the cell directly ABOVE it.  Each maze must have 6 doors.
// patch_doors counts through them from the last to the first.
.macro DoorWords(rows) {
    .var count = 0
    .for (var r = 1; r < 19; r++) {
        .for (var c = 1; c < 21; c++) {
            .if (rows.get(r).charAt(c) == '+') {
                .eval count = count + 1
                .if (r < 10) {
                    .word MAZE_TOP + (r-1)*22 + c
                } else {
                    .word MAZE_BOTTOM + (r-1-10)*22 + c
                }
            }
        }
    }
    .errorif count != 6, "each maze must have exactly 6 doors"
}
doorTable:
    DoorWords(mazeRows1)
    DoorWords(mazeRows2)
    DoorWords(mazeRows3)

// Dots in each maze (every '.' in the picture): the level ends when all are eaten.
.function countDots(rows) {
    .var n = 0
    .for (var r = 0; r < 20; r++) {
        .for (var c = 0; c < 22; c++) {
            .if (rows.get(r).charAt(c) == '.') .eval n = n + 1
        }
    }
    .return n
}
.const DOTS1 = countDots(mazeRows1)
.const DOTS2 = countDots(mazeRows2)
.const DOTS3 = countDots(mazeRows3)
.errorif DOTS1 > 255 || DOTS2 > 255 || DOTS3 > 255, "dot count must fit in a byte"

// Per-maze values, indexed by mazeNumber (0, 1 or 2)
wallOffsetTable: .byte 0, 56, 112
doorOffsetTable: .byte 0, 12, 24
dotTotalTable:   .byte DOTS1, DOTS2, DOTS3

// The five cells of a door, relative to the 'above the hub' cell
cellOffset:  .byte 0,  21,  22,  23, 44
cellChar:    .byte $20,$1B,$1F,$1C,$20     // blank, left arm, hub, right arm, blank
cellColour:  .byte 7,   6,   6,   6,  7

// ======================================================================
// CUSTOM CHARACTER SET  ($1C00-$1DD7 = 59 characters of 8 bytes)
// Character N is screen code N.  The VIC reads it from $1C00 + N*8.
// Pixel art is shown beside each byte  (# = pixel on).
// ======================================================================
.pc = $1C00 "Character set"       // the VIC reads characters from $1C00 ($9005 = $FF): this address is fixed
charset:
    // $00  splat (last frame of the player's death)
    .byte %11000011   // ##....##
    .byte %11011011   // ##.##.##
    .byte %00100100   // ..#..#..
    .byte %01011010   // .#.##.#.
    .byte %01011010   // .#.##.#.
    .byte %00100100   // ..#..#..
    .byte %11011011   // ##.##.##
    .byte %11000011   // ##....##
    .byte $3C,$24,$24,$7E,$62,$62,$62,$00   // $01  letter A
    .byte $7C,$22,$22,$3C,$32,$32,$7C,$00   // $02  letter B
    .byte $7E,$42,$40,$60,$60,$62,$7E,$00   // $03  letter C
    .byte $7E,$22,$22,$32,$32,$32,$7E,$00   // $04  letter D
    .byte $7E,$42,$40,$78,$60,$62,$7E,$00   // $05  letter E
    .byte $7E,$42,$40,$78,$60,$60,$60,$00   // $06  letter F
    .byte $7E,$42,$40,$6E,$62,$62,$7E,$00   // $07  letter G
    .byte $42,$42,$42,$7E,$62,$62,$62,$00   // $08  letter H
    .byte $10,$10,$10,$18,$18,$18,$18,$00   // $09  letter I
    .byte $0E,$04,$04,$0C,$0C,$4C,$7C,$00   // $0A  letter J
    .byte $42,$44,$48,$70,$68,$64,$62,$00   // $0B  letter K
    .byte $40,$40,$40,$60,$60,$62,$7E,$00   // $0C  letter L
    .byte $FE,$92,$92,$D2,$D2,$D2,$D2,$00   // $0D  letter M
    .byte $42,$62,$52,$6A,$66,$62,$62,$00   // $0E  letter N
    .byte $7E,$42,$42,$62,$62,$62,$7E,$00   // $0F  letter O
    .byte $7E,$42,$42,$7E,$60,$60,$60,$00   // $10  letter P
    .byte $7E,$42,$42,$62,$6A,$64,$7A,$00   // $11  letter Q
    .byte $7E,$42,$42,$7E,$68,$64,$62,$00   // $12  letter R
    .byte $7E,$42,$40,$7E,$02,$62,$7E,$00   // $13  letter S
    .byte $3E,$08,$08,$0C,$0C,$0C,$0C,$00   // $14  letter T
    .byte $42,$42,$42,$62,$62,$62,$7E,$00   // $15  letter U
    .byte $42,$42,$42,$34,$34,$18,$18,$00   // $16  letter V
    .byte $92,$92,$92,$D2,$D2,$D2,$FE,$00   // $17  letter W
    .byte $42,$42,$24,$18,$34,$62,$62,$00   // $18  letter X
    .byte $42,$42,$42,$7E,$18,$18,$18,$00   // $19  letter Y
    .byte $7E,$46,$0C,$18,$30,$62,$7E,$00   // $1A  letter Z
    // $1B  door arm: LEFT
    .byte %11000000   // ##......
    .byte %11000000   // ##......
    .byte %11111111   // ########
    .byte %11101010   // ###.#.#.
    .byte %11010101   // ##.#.#.#
    .byte %11111111   // ########
    .byte %11000000   // ##......
    .byte %11000000   // ##......
    // $1C  door arm: RIGHT
    .byte %00000011   // ......##
    .byte %00000011   // ......##
    .byte %11111111   // ########
    .byte %10101011   // #.#.#.##
    .byte %01010111   // .#.#.###
    .byte %11111111   // ########
    .byte %00000011   // ......##
    .byte %00000011   // ......##
    // $1D  door arm: TOP
    .byte %11111111   // ########
    .byte %11111111   // ########
    .byte %00110100   // ..##.#..
    .byte %00101100   // ..#.##..
    .byte %00110100   // ..##.#..
    .byte %00101100   // ..#.##..
    .byte %00110100   // ..##.#..
    .byte %00101100   // ..#.##..
    // $1E  door arm: BOTTOM
    .byte %00110100   // ..##.#..
    .byte %00101100   // ..#.##..
    .byte %00110100   // ..##.#..
    .byte %00101100   // ..#.##..
    .byte %00110100   // ..##.#..
    .byte %00101100   // ..#.##..
    .byte %11111111   // ########
    .byte %11111111   // ########
    // $1F  door hub
    .byte %00111100   // ..####..
    .byte %01100110   // .##..##.
    .byte %11100111   // ###..###
    .byte %10011001   // #..##..#
    .byte %10011001   // #..##..#
    .byte %11100111   // ###..###
    .byte %01100110   // .##..##.
    .byte %00111100   // ..####..
    // $20  space
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    // $21  WALL
    .byte %11111111   // ########
    .byte %10100101   // #.#..#.#
    .byte %11000011   // ##....##
    .byte %10011001   // #..##..#
    .byte %10011001   // #..##..#
    .byte %11000011   // ##....##
    .byte %10100101   // #.#..#.#
    .byte %11111111   // ########
    // $22  DOT
    .byte %00000000   // ........
    .byte %00111100   // ..####..
    .byte %01100110   // .##..##.
    .byte %01011010   // .#.##.#.
    .byte %01011010   // .#.##.#.
    .byte %01100110   // .##..##.
    .byte %00111100   // ..####..
    .byte %00000000   // ........
    // $23  player frame 1
    .byte %01000100   // .#...#..
    .byte %00101000   // ..#.#...
    .byte %11111110   // #######.
    .byte %10010010   // #..#..#.
    .byte %11011010   // ##.##.#.
    .byte %11111110   // #######.
    .byte %00101000   // ..#.#...
    .byte %01101100   // .##.##..
    // $24  player frame 2
    .byte %01000100   // .#...#..
    .byte %00101000   // ..#.#...
    .byte %11111110   // #######.
    .byte %11011010   // ##.##.#.
    .byte %10010010   // #..#..#.
    .byte %11111110   // #######.
    .byte %00101000   // ..#.#...
    .byte %01101100   // .##.##..
    // $25  player frame 3
    .byte %01000100   // .#...#..
    .byte %00101000   // ..#.#...
    .byte %11111110   // #######.
    .byte %10110110   // #.##.##.
    .byte %10010010   // #..#..#.
    .byte %11111110   // #######.
    .byte %00101000   // ..#.#...
    .byte %01101100   // .##.##..
    // $26  player frame 4
    .byte %01000100   // .#...#..
    .byte %00101000   // ..#.#...
    .byte %11111110   // #######.
    .byte %10010010   // #..#..#.
    .byte %10110110   // #.##.##.
    .byte %11111110   // #######.
    .byte %00101000   // ..#.#...
    .byte %01101100   // .##.##..
    // $27  enemy frame 1
    .byte %01111100   // .#####..
    .byte %11111110   // #######.
    .byte %10010010   // #..#..#.
    .byte %11111110   // #######.
    .byte %01101100   // .##.##..
    .byte %01010100   // .#.#.#..
    .byte %11000100   // ##...#..
    .byte %00000110   // .....##.
    // $28  enemy frame 2
    .byte %00111110   // ..#####.
    .byte %01111111   // .#######
    .byte %01001001   // .#..#..#
    .byte %01111111   // .#######
    .byte %00110110   // ..##.##.
    .byte %00101010   // ..#.#.#.
    .byte %00100011   // ..#...##
    .byte %01100000   // .##.....
    // $29  bomb cloud (spray)
    .byte %00000000   // ........
    .byte %01100110   // .##..##.
    .byte %01011010   // .#.##.#.
    .byte %00100100   // ..#..#..
    .byte %00100100   // ..#..#..
    .byte %01011010   // .#.##.#.
    .byte %01100110   // .##..##.
    .byte %00000000   // ........
    // $2A  death spin frame 1
    .byte %01000100   // .#...#..
    .byte %00101000   // ..#.#...
    .byte %11111110   // #######.
    .byte %10010010   // #..#..#.
    .byte %10010010   // #..#..#.
    .byte %11111110   // #######.
    .byte %00101000   // ..#.#...
    .byte %01101100   // .##.##..
    // $2B  death spin frame 2
    .byte %00111101   // ..####.#
    .byte %10100101   // #.#..#.#
    .byte %11100110   // ###..##.
    .byte %00111100   // ..####..
    .byte %11100110   // ###..##.
    .byte %10100101   // #.#..#.#
    .byte %00111101   // ..####.#
    .byte %00000000   // ........
    // $2C  death spin frame 3
    .byte %00110110   // ..##.##.
    .byte %00010100   // ...#.#..
    .byte %01111111   // .#######
    .byte %01001001   // .#..#..#
    .byte %01001001   // .#..#..#
    .byte %01111111   // .#######
    .byte %00010100   // ...#.#..
    .byte %01100011   // .##...##
    // $2D  death spin frame 4
    .byte %00000000   // ........
    .byte %10111100   // #.####..
    .byte %10100101   // #.#..#.#
    .byte %01100111   // .##..###
    .byte %00111100   // ..####..
    .byte %01100111   // .##..###
    .byte %10100101   // #.#..#.#
    .byte %10111100   // #.####..
    // $2E  small dot (death animation)
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00011000   // ...##...
    .byte %00011000   // ...##...
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %00000000   // ........
    // $2F  ring (death animation)
    .byte %00000000   // ........
    .byte %00011000   // ...##...
    .byte %00100100   // ..#..#..
    .byte %01011010   // .#.##.#.
    .byte %01011010   // .#.##.#.
    .byte %00100100   // ..#..#..
    .byte %00011000   // ...##...
    .byte %00000000   // ........
    .byte $7E,$42,$46,$7A,$62,$62,$7E,$00   // $30  digit 0
    .byte $08,$18,$28,$0C,$0C,$0C,$3E,$00   // $31  digit 1
    .byte $7E,$42,$02,$7E,$60,$62,$7E,$00   // $32  digit 2
    .byte $7E,$42,$02,$3E,$02,$62,$7E,$00   // $33  digit 3
    .byte $0C,$14,$24,$4C,$7E,$0C,$0C,$00   // $34  digit 4
    .byte $7E,$42,$7C,$06,$06,$66,$7C,$00   // $35  digit 5
    .byte $7E,$42,$40,$7E,$62,$62,$7E,$00   // $36  digit 6
    .byte $7E,$42,$02,$06,$06,$06,$06,$00   // $37  digit 7
    .byte $7E,$42,$42,$7E,$62,$62,$7E,$00   // $38  digit 8
    .byte $7E,$42,$42,$7E,$02,$62,$7E,$00   // $39  digit 9
    // $3A  ':' 
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %01111110   // .######.
    .byte %00000000   // ........
    .byte %00000000   // ........
    .byte %01111110   // .######.
    .byte %00000000   // ........
    .byte %00000000   // ........

// ======================================================================
// rowOffset: offset of each maze row from the start of its half of the screen.
// Rows 0-9 use the top half, rows 10-19 the bottom half, hence the repeat.
// ======================================================================
rowOffset:   .byte 0,22,44,66,88,110,132,154,176,198   // $1DE0
             .byte 0,22,44,66,88,110,132,154,176,198

// More variables ($1DF4-$1DFF)
playerRow:   .byte $0E            // $1DF4  player row 0-19 (start 14)
tempRow:      .byte $01            // $1DF5  scratch: destination row / "move allowed" result / enemy number
playerCol:   .byte $0A            // $1DF6  player column 0-21 (start 10)
tempCol:      .byte $03            // $1DF7  scratch: destination column / direction tried
playerFrame: .byte $25            // $1DF8  player animation frame $23-$26
targetChar:   .byte $20            // $1DF9  character found on the destination cell
bombs:        .byte $05            // $1DFA  bombs left (0-9)
enemyLimit:   .byte $02            // $1DFC  number of enemies + 1 (2-6): last enemy number processed
enemyFrame:   .byte $28            // $1DFD  enemy animation frame $27 / $28
wanderDir:    .byte $03            // $1DFE  cycling direction 2-5 used when an enemy is stuck
dotsEaten:    .byte $00            // $1DFF  dots eaten this level
mazeNumber:   .byte $00            // 0 = maze 1, 1 = maze 2 (swaps every level, reset to 0 for a new game)
wallBase:     .byte $00            // start of this maze's bitmaps in wallBits (set by draw_maze)
doorBase:     .byte $00            // start of this maze's doors in doorTable (set by draw_maze)
dotTarget:    .byte $00            // dots in this maze: the level ends when dotsEaten reaches this
levelTens:    .byte $30            // level number as two ASCII digits ('01' at the start of a game)
levelUnits:   .byte $31
tuneIndex:    .byte $00            // play_tune: position in tuneData
tuneDur:      .byte $00            // play_tune: length units left in the current note
tuneSkip:     .byte $00            // play_tune: $20 = stop when FIRE is pressed
