# Brainzig
A simple [Brainfuck](https://en.wikipedia.org/wiki/Brainfuck) interpreter I hacked together in Zig
(works with 0.13.0, not higher).

I saw a short Brainfuck program, which my brain—surprise surprise—didn't parse very well, so I
wrote an interpreter to read it for me.

The program is included as [`src/bf/hi.bf`](src/bf/hi.bf ), so you can run `brainzig hi.bf`, or `zig build run -- src/bf/hi.bf`
to test it out!

## [`src/bf/short.bf`](src/bf/short.bf ), [`src/bf/medium.bf`](src/bf/medium.bf ), and [`src/bf/long.bf`](src/bf/long.bf)
I generated some 150 paragraphs of lorem ipsum on a website I sadly don't remember.

I then converted this text into highly inefficient Brainfuck code, giving me [`src/bf/long.bf`](src/bf/long.bf ).
I wanted to see what kind of speedup I could get from doing most of the work at compile time, by running
`zig build --release=fast -Dfile=long.bf -Dname=long`.
The `-Dfile` option loads the Brainfuck code at compile time.

This means you can no longer use the
resulting binary as an interpreter of arbitrary Brainfuck code, so I also included a `-Dname` option to
allow you to give the binary a different name.

Running `brainzig < long.bf > /dev/null` takes ~0.35s on my machine.
This is quite a bit faster than the ~8s it takes to run `brainzig long.bf > /dev/null`, which likely takes
longer because it does not allocate memory to hold the file, seeking through the file directly instead.

So how long does `long` take, after compiling [`long.bf`](src/bf/long.bf) directly into the source?
Turns out that was quite a difficult question to answer!
As soon as I tried compiling it, Zig got mad at me because it hit the limit of 1,000 backward branches.
Full disclosure: I don't really know what that means. But I do know that you can raise that number!

I started by doubling it from the default of 1,000 to 2,000. Not enough, so 4,000. No? 8,000? 20,000?
Still not enough, huh? Alright, about about 200,000?
There it went! It finally started actually comp—oh. 200,000 was still not enough.
Deciding that I didn't care about some optimal number, I simply cranked it up to 200,000,000 and let it rip!
Now it turns out that compiling it takes quite a while.
A very long while.

After a few *hours* of waiting, I decided to create a shorter version of [`long.bf`](src/bf/long.bf ), which you can find
in [`src/bf/short.bf`](src/bf/short.bf ). It is a single paragraph of the original 150.
This took a couple of seconds to compile, so I decided to try with five paragraphs next ([`src/bf/medium.bf`](src/bf/medium.bf )).
That took over two and a half minutes.
Whatever the compiler was doing was clearly not a linear slowdown.

After some napkin math, I was fairly confident that I was looking at O(n²) time, n being the
number of Brainfuck instructions.
This would also mean that the compilation of `long`, which has been going on for a `long` time already,
was going to take on the order of 40 hours.
I had let the compiler work overnight, with my PC inconveniently located in my bedroom.

The next day, I started getting worried about memory consumption.
My system has 64GB of RAM, but it already ate up a sizable chunk of that at only 17 hours into compilation.
Luckily, my worries were not warranted!
Instead of running out of RAM, I found out that the limit of 200,000,000 backward branches was not enough.

...

Alright. 200,000,000,000 it is. Oh, it's a `u32`? Okay well then 4,294,967,295 it is, but that better be enough!
And it was!! After only 29 hours and 20 minutes, it was finally done compiling!
The original source file, [`src/bf/long.bf`](src/bf/long.bf ), is about 17MB in size, while the compiled binary went all the way down
to 6MB!
Talk about optimization!

But the real question remains!
How much faster is it?
If you were hoping it was somehow slower, I have to disappoint you!
Execution time went down to about 0.014s!! 
It was all worth it in the end!

## A bit faster

To learn more about the Zig build system, I decided to write two preprocessors for the Brainfuck source code.
The first preprocessor simplifies the code by omitting all comments and doing a simple form of run length encoding
with the instructions. For example, `+++` becomes `+3`.
As these may occasionally cancel out, like `++-` becoming `+1`, the length can be zero, as in `+++++-----`.
For these cases, the instructions are simply omitted.

Such an omission can lead to instructions still not being encoded together, like in the case of `.++--.`,
which reduces down to `.1 .1`.
That's where the second preprocessor comes in and simply adds any remaining duplicates together.

These simplified versions of the Brainfuck code are generated at compile time when passing a `-Dfile`.
That means the file that is to be embedded in [`main.zig`](src/main.zig) does not exist at compile time!
Luckily, if you check [`build.zig`](build.zig ), you will find that I was able to make [`main.zig`](src/main.zig)
depend on the outputs of the preprocessors!

Doing this preprocessing on the Brainfuck code itself, instead of doing it after parsing it in [`main.zig`](src/main.zig ),
makes compilation times a bit shorter, by removing the first slow step during compilation.
It now no longer takes 29 and 20 minutes to compile, but just five... minutes!!
