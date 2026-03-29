# Seeds for My App
#
# Run with: mix run priv/repo/seeds.exs

alias MyApp.{Repo, Post, AgentConfig}

# --- Admin User ---

case Sigil.Auth.register(%{email: "admin@example.com", password: "admin123"}) do
  {:ok, _user} -> IO.puts("✓ Created admin user: admin@example.com / admin123")
  {:error, _} -> IO.puts("· Admin user already exists")
end

# --- Blog Posts ---

posts = [
  %{
    title: "Clarity before alignment",
    body: """
    Teams often push for alignment too early. The deeper need is usually a shared understanding of what matters, what has changed, and what kind of motion is actually required.

    When people say they need alignment, they are often naming the discomfort of ambiguity. But alignment without clarity becomes performance. People start repeating decisions they do not fully understand, and the work becomes heavier instead of lighter.

    The better starting point is shared orientation. What are we trying to move? What is still uncertain? What matters now more than it mattered last month? Once those answers are visible, alignment becomes a consequence rather than a demand.
    """,
    tags: ["strategy", "teams"],
    published: true,
    published_at: ~U[2025-05-24 12:00:00Z]
  },
  %{
    title: "Systems should reduce friction",
    body: """
    A useful system does not exist to prove that work is being managed. It exists to make the next right action easier, clearer, and more repeatable.

    Many systems begin as an answer to chaos and quietly become a new source of drag. Meetings expand, statuses multiply, and people spend more time tending the system than being supported by it.

    A good test is simple: after using the system, do people feel less confused and more capable? If the answer is no, it may be organized, but it is not helping.
    """,
    tags: ["systems", "work"],
    published: true,
    published_at: ~U[2025-05-18 12:00:00Z]
  },
  %{
    title: "Notes on building with intention",
    body: """
    Intentional building has less to do with speed than with honesty. What are you really trying to create, and what are you pretending you need because everyone around you seems to want it?

    Clear constraints can be generous. They reduce the number of false options and return attention to the few things that might actually matter.

    Over time, intention creates a different emotional texture around work. There is less scrambling, less imitation, and more willingness to let something become itself slowly.
    """,
    tags: ["leadership", "life"],
    published: true,
    published_at: ~U[2025-05-12 12:00:00Z]
  },
  %{
    title: "Useful products teach people how to use them",
    body: """
    The best products reduce explanation over time. They do not rely on long instructions because their structure quietly teaches the user what matters and what to do next.

    When a product repeatedly needs translation, the problem may not be messaging. It may be that the product is asking too much interpretation from the user.

    Good product design is a form of embodied clarity. It lets people feel the logic of the thing without needing to decode it first.
    """,
    tags: ["product", "strategy"],
    published: true,
    published_at: ~U[2025-05-06 12:00:00Z]
  },
  %{
    title: "The pace that lets you think",
    body: """
    There is a pace of work that keeps a team alive, and there is a pace of work that keeps a team reactive. They can look similar from the outside for a while, but they produce very different decisions.

    When the rhythm is too fast, people borrow certainty from urgency. They decide quickly not because something is clear, but because the speed itself creates pressure to close.

    A healthier rhythm leaves room for signal. It gives enough time for real noticing, which is often the difference between motion and meaningful progress.
    """,
    tags: ["journal", "work"],
    published: true,
    published_at: ~U[2025-04-29 12:00:00Z]
  },
  %{
    title: "What trust sounds like in a team",
    body: """
    Trust is not just a feeling. It has a sound. It sounds like people saying what they see before they know how it will land. It sounds like dissent without drama and uncertainty without shame.

    In low-trust environments, people edit themselves toward safety. In high-trust environments, they contribute while the thinking is still alive.

    The shift matters because teams do not build clarity only through decisions. They build it through the quality of what can be said out loud.
    """,
    tags: ["leadership", "teams"],
    published: true,
    published_at: ~U[2025-04-21 12:00:00Z]
  },
  %{
    title: "Simplicity is a discipline",
    body: """
    Simple systems are rarely the result of doing less thinking. More often, they come from deeper thinking followed by disciplined subtraction.

    Complexity can create the feeling of thoroughness. Simplicity asks more of us because it reveals whether we actually understand the thing well enough to make it clear.

    This is one reason simplicity feels expensive at first. It requires patience, taste, and the willingness to remove what you once defended.
    """,
    tags: ["systems", "journal"],
    published: true,
    published_at: ~U[2025-04-14 12:00:00Z]
  },
  %{
    title: "Making room for the second thought",
    body: """
    The first thought is often useful, but it is rarely the whole thing. The second thought carries more context, more humility, and sometimes a better question.

    Modern work rewards immediacy, which can train us to treat quickness as intelligence. But many worthwhile insights arrive a little later, after the nervous system settles and the obvious answer loses its shine.

    Creating room for the second thought is not slowness for its own sake. It is respect for depth.
    """,
    tags: ["life", "work"],
    published: true,
    published_at: ~U[2025-04-07 12:00:00Z]
  },
  %{
    title: "Choosing what not to build",
    body: """
    Every product carries a hidden philosophy in what it refuses. The things you do not build shape the experience just as much as the features you ship.

    Restraint is difficult when possibility feels abundant. But abundance is exactly what makes judgment necessary. Without a point of view, a roadmap becomes a list of unattended desires.

    What matters is not minimalism as an aesthetic. It is coherence as a practice.
    """,
    tags: ["strategy", "product"],
    published: true,
    published_at: ~U[2025-03-31 12:00:00Z]
  },
  %{
    title: "The work of naming what matters",
    body: """
    Leadership often begins with language. Not polished language, but accurate language. The ability to name what is happening, what is needed, and what people may be avoiding.

    When important things stay unnamed, teams fill the silence with assumption. Over time, assumption hardens into culture.

    One of the simplest ways to change a system is to describe it clearly enough that people can finally see it together.
    """,
    tags: ["journal", "leadership"],
    published: true,
    published_at: ~U[2025-03-24 12:00:00Z]
  }
]

for post_attrs <- posts do
  case Repo.get_by(Post, title: post_attrs.title) do
    nil ->
      %Post{}
      |> Post.changeset(post_attrs)
      |> Repo.insert!()

      IO.puts("✓ Created post: #{post_attrs.title}")

    _existing ->
      IO.puts("· Post exists: #{post_attrs.title}")
  end
end

# --- Agent Configs ---

agents = [
  %{
    name: "Blog Assistant",
    slug: "blog-assistant",
    system_prompt: """
    You are a friendly assistant for My App, a personal blog about strategy, systems, leadership, work, and life.

    You can search blog posts to help answer questions about the author's writing. When you find relevant posts, reference them by title and share key ideas.

    Be concise and thoughtful. Match the tone of the blog — reflective, clear, and honest. Keep responses to 2-3 short paragraphs at most.

    If someone asks about a topic not covered in the blog, be honest about it and offer to help in other ways.
    """,
    model: "claude-sonnet-4-20250514",
    active: true,
    tools: []
  },
  %{
    name: "Scheduler",
    slug: "scheduler",
    system_prompt: """
    You are the scheduling assistant. Your job is to help people who want
    to connect set up a meeting.

    ## Your Process

    1. When someone expresses interest in connecting , warmly
       acknowledge their interest.

    2. Before checking availability, you MUST learn three things:
       - Their **name**
       - **What they'd like to discuss** 
       - **How they found** the blog (optional — ask naturally, don't demand)

       Ask these conversationally, not as a checklist. It's okay to gather
       this over a few messages.

    3. **Sales pitch detection**: If the person's topic is clearly a sales
       pitch, product demo request, or cold outreach, politely decline:
       "Thanks for your interest, but We aren't taking sales meetings through
       the blog at this time. Feel free to reach out via email for business
       inquiries." Do NOT check the calendar for sales pitches.

    4. Once you have the name and a genuine topic, use the `check_calendar`
       tool to find available slots. Present 3 options.

    5. After the user picks a time, ask for their **email address** so you
       can send the calendar invite.

    6. Use the `book_meeting` tool with all the collected information.

    7. Confirm the booking with a friendly summary.

    ## Tone

    Be warm, professional, and concise. Be welcoming
    but respect his time. Keep messages short and conversational.

    ## Important

    - Meetings are 30 minutes
    - Only offer times from the `check_calendar` tool results
    - Never fabricate availability
    - If the calendar tool shows no availability, apologize and suggest
      they try again next week
    """,
    model: "claude-sonnet-4-20250514",
    active: true,
    tools: ["check_calendar", "book_meeting"]
  }
]

for agent_attrs <- agents do
  case Repo.get_by(AgentConfig, slug: agent_attrs.slug) do
    nil ->
      %AgentConfig{}
      |> AgentConfig.changeset(agent_attrs)
      |> Repo.insert!()

      IO.puts("✓ Created agent: #{agent_attrs.name}")

    _existing ->
      IO.puts("· Agent exists: #{agent_attrs.name}")
  end
end

IO.puts("\n✓ Seeds complete!")
