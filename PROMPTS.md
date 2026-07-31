# The prompts

Unedited, typos intact. That's the point: you don't need clean prompts, you need clear intent and honest feedback about what's broken.

Built with [Claude Code](https://claude.com/claude-code).

---

**1. The whole thing**

> can u build an app and intsall on my iphone for me? a teleprompter that uses voice regcog

→ App skeleton, signed and installed on the phone.

---

**2. The real requirement**

> If you can do it, I want to have something that floats on the screen. It can float on the screen so I can use my actual camera to shoot, and it just floats right there. For example, when I open the camera and go to video, even though I'm shooting, the teleprompter stays on the screen. When I start talking, it starts moving. We are also using an open-source speech recognition system, so if I stop or talk about something else, it won't move.

→ Picture-in-Picture overlay that survives leaving the app.

---

**3. Naming it**

> lets call it Reeb

---

**4. Completing it**

> I want you to complete the whole system. Specifically, I should be able to add more scripts whenever I want to. I would also like to add more aesthetics.

→ Script library, dark theme, app icon.

---

**5. The two real bugs**

> The speech recognition automatically ends at a point. I don't know why, when I'm talking, it just doesn't continue anymore. Fix that. And also, the speech recognition is strange. You know, when there are other words in the script that look the same, it will jump to those words even though I've not reached there.

→ The watchdog and generation counter; the two-word rule for jumps.

---

**6. Blending the engines**

> can u blenf whoper and the apple thing?

→ Apple streaming for speed + whisper.cpp verification for accuracy.

---

**7. Speed**

> AND IT SHOULD BE LIGHTINING FASTTTTTTTTTTTT MAN

→ Release build instead of debug, cached row layout, scroll cut from 350 ms to 150 ms.

---

**8. Reporting a bug with a screenshot**

> *(screenshot of the floating window rendering black over the Camera app)*
> when i open camera

→ Found the missing `controlTimebase` on the display layer.

---

**9. The one that changed the architecture**

> if i open cam it vanishing i want to use it while i am shooting

→ A full camera recorder built into the app, with audio forked to speech recognition.

---

## What worked

- **Describe outcomes, not implementations.** "It should follow my voice" got a better result than any instruction about APIs would have.
- **Report bugs like a user.** "it just doesn't continue anymore" was enough to find a race condition.
- **Screenshots beat descriptions.** One screenshot of a black window located a bug that words had failed to pin down across several turns.
- **Push back on the first answer.** "we good?" and "u can do better" produced real fixes, not politeness.
