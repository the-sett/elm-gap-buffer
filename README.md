**Contacts for Support**
- @rupertlssmith on https://elmlang.slack.com
- @rupert on https://discourse.elm-lang.org

**Status**

- 06-Sep-2023 - Published as version 1.0.0

# elm-gap-buffer

A gap buffer implementation for Elm. This is efficent as it is based around slicing of Array.

A gap buffer consists of a head array, a current position and item at that position, and a tail array. The current position can be moved around by rebuilding the head or tail arrays as it moves. Editing at the current position is directly onto it, and extremely fast. The current position can also be off the end, in which case there is no item at the current position, and no tail array.

This can be thought of as like a List zipper, but with a more efficient implementation. A code editor capable of working with millions of lines of code whilst scrolling and editing smoothly and quickly has been demonstrated using this.