# jshint devel:true

re_grouping = /\D+|\d+(\.\d+)?[ETGMkmμnpf]?/g

# Smart comparison function used with Array.prototype.sort. It is able to compare numbers
# and suffixes by value rather than by character. For example, '1MB' will come before '1GB',
# and 'v10' will come after 'v9'.
smartSort = (str1, str2) ->
    match1 = (str1 + '').match re_grouping
    match2 = (str2 + '').match re_grouping

    for i in [0...Math.min match1.length, match2.length]
        if !isNaN(parseInt match1[i]) and !isNaN(parseInt match2[i])
            diff = revSmartPrefix(match1[i]) - revSmartPrefix(match2[i])
            return diff if diff != 0
            continue
        m1 = match1[i].toUpperCase()
        m2 = match2[i].toUpperCase()
        return -1 if m1 < m2
        return 1 if m1 > m2

    match1.length - match2.length

# Same as smartSort but reversed
revSmartSort = (str1, str2) -> (-smartSort str1, str2)

_smartUnits = (values, names, precisions) ->
    (value) ->
        for i in [0...values.length]
            continue if value < values[i]
            return (value / values[i]).toPrecision(
                precisions[Math.min precisions.length - 1, i]) + names[i]
        (value.toPrecision precisions[precisions.length - 1]) + names[names.length - 1]

_revSmartUnits = (values, names) ->
    (value) ->
        value = value + ''
        for i in [0...values.length]
            continue if value.indexOf(names[i], value.length - names[i].length) < 0
            return +(value.slice 0, value.length - names[i].length) * values[i]
        parseFloat value

# Format a floating-point number by adding the appropriate SI-prefix and rounding to
# appropriate digits. e.g. smartPrefix(0.001) === '1m'
smartPrefix = _smartUnits(
    [1e15, 1e12, 1e9, 1e6, 1e3, 1, 1e-3, 1e-6, 1e-9, 1e-12, 1e-15]
    ['E', 'T', 'G', 'M', 'k', '', 'm', 'μ', 'n', 'p', 'f', '']
    [3])

# Parse a string of a number with SI-prefix into its equivalent floating-point number.
# e.g. revSmartPrefix('1m') === 0.001
revSmartPrefix = _revSmartUnits(
    [1e15, 1e12, 1e9, 1e6, 1e3, 1e-3, 1e-6, 1e-9, 1e-12, 1e-15, 1]
    ['E', 'T', 'G', 'M', 'k', 'm', 'μ', 'n', 'p', 'f', ''])

# Format a number of seconds into appropriate time units. e.g. smartTime(3600) === '1h'
smartTime = _smartUnits(
    [31556952, 604800, 86400, 3600, 60, 1, 1e-3, 1e-6, 1e-9, 1e-12]
    ['y', 'w', 'd', 'h', 'm', 's', 'ms', 'μs', 'ns', 'ps', 's']
    [2, 2, 2, 2, 2, 3])

# Format a fraction number into a percentage. e.g. smartPercent(0.1) === '10.0%'
smartPercent = (v) -> ((v * 100).toPrecision(3) + "%")

binarySearch = (arr, value, fn) ->
    fn ?= (v) -> v
    [lo, hi] = [0, arr.length]
    i = Math.floor (lo + hi) / 2
    [iv, ivp1] = [fn(arr[i]), fn(arr[i + 1])]
    until iv < value and not (ivp1 < value)
        lo = i + 1 if ivp1 < value
        hi = i if not (iv < value)
        return hi if lo >= hi
        i = Math.floor (lo + hi) / 2
        [iv, ivp1] = [fn(arr[i]), fn(arr[i + 1])]
    i + 1

escapeHTML = (str) -> (str && str.replace(/</g, "&lt;").replace(/>/g, "&gt;"))

drawn_frames = []

getLabel = (thread, idx) ->
    label = thread.stringTable[idx]
    lpar = label.lastIndexOf "("
    slash = label.lastIndexOf "/"
    colon = label.lastIndexOf ":"
    if lpar >= 0 and slash > lpar and colon > slash
        # method (file:line)
        return label[...lpar + 1] + label[slash + 1...]
    else if lpar < 0 and slash >= 0 and colon > slash
        # file:line
        return label[slash + 1...]
    label.replace "(<native>:0)", "<native>"

skipLabel = (label) ->
    label in ["js::RunScript", "import <native>"]

setSlider = (elems, thread) ->
    slider = elems.slider
    min = thread.trace.data[0][1]
    max = thread.trace.data[thread.trace.data.length - 1][1]

    slider.rangeSlider
        bounds:
            min: min
            max: max
        defaultValues:
            min: min
            max: (max - min) * 2 / 3 + min
        range:
            min: 15 * (max - min) / slider.width()
        formatter: (value) -> (Math.round(value) + "ms")
        valueLabels: "change"

populateTiming = (elems, thread, range) ->
    table = elems.table
    start = binarySearch thread.trace.data, range.min, (t) -> t?[1]
    end = binarySearch thread.trace.data, range.max, (t) -> t?[1]

    stack = []
    labels = []
    stats = {}

    for i in [start...end]
        [prevTime, time] = [time, thread.trace.data[i][1]]

        label = getLabel thread, thread.trace.data[i][0]
        prevLabel = if label.length then stack[stack.length - 1] else stack.pop()
        stack.push label if label.length

        if not prevLabel?
            continue

        if not stats[prevLabel]?
            labels.push prevLabel
            stats[prevLabel] =
                count: if label.length then 0 else 1
                time: time - prevTime
            continue

        stats[prevLabel].count++ if not label.length
        stats[prevLabel].time += time - prevTime

    for label in stack
        continue if not stats[label]
        stats[label].count++

    labels.sort (a, b) -> (stats[b].time - stats[a].time)
    table.empty()
    for label, i in labels
        stat = stats[label]
        table.append(
            $("<tr/>").append(
                $("<td/>").text label
                $("<td/>").text stat.count
                $("<td/>").text (stat.time / stat.count).toFixed(3)
                $("<td/>").text stat.time.toFixed(3)
            ))

    $.bootstrapSortable()

redraw = (elems, thread, options) ->
    plot = elems.plot
    min = options.range.min # time at start of view
    duration = options.range.max - options.range.min # time duration inside view
    # index of frame that first starts in view
    start = binarySearch thread.trace.data, min, (t) -> t?[1]
    # index of frame that last ends in view
    end = binarySearch thread.trace.data, options.range.max, (t) -> t?[1]

    options.filter = options.filter and options.filter.toLowerCase()

    WIDTH = plot.width()
    HEIGHT = plot.height()
    FRAME_STRIDE = HEIGHT / 25
    FRAME_HEIGHT = FRAME_STRIDE * 0.8
    MIN_FRAME_WIDTH = 4 / WIDTH
    FONT_HEIGHT = parseFloat(plot.css('fontSize'))
    MARKER_SPACING = 5
    HEADER_HEIGHT = 1.5 * FRAME_HEIGHT
    MAX_PAINT_MARKERS = 4

    ctx = plot[0].getContext "2d"
    ctx.font = "1em sans-serif"
    ctx.textAlign = "left"
    ctx.textBaseline = "top"
    ctx.fillStyle = "#fff"
    ctx.fillRect 0, 0, WIDTH, HEIGHT

    marker_end = []
    ctx.beginPath()
    for m in thread.markers.data
        [label, time, data] = m
        if time < min
            continue
        if time >= min + duration
            break

        label = thread.stringTable[label]
        if (data and data.type in ["tracing", "GCMinor", "GCSlice", "DOMEvent"]) or
           label.startsWith("Bailout_") or
           label.startsWith("Navigation::")
            continue

        left = (time - min) / duration * WIDTH
        for line in [0...marker_end.length] by 1
            if marker_end[line] < left
                break
        marker_end.push 0 while line >= marker_end.length

        top = line * FRAME_HEIGHT + HEADER_HEIGHT
        ctx.strokeStyle = "#ccc"
        ctx.moveTo left, top
        ctx.lineTo left, HEIGHT

        ctx.fillStyle = "#888"
        ctx.fillText label, left + MARKER_SPACING, top
        metrics = ctx.measureText label
        marker_end[line] = left + metrics.width + 2 * MARKER_SPACING
    ctx.stroke()

    # ruler_scale = Math.pow 10, "#{Math.floor 50 * duration / WIDTH}".length
    # ruler_start = ruler_scale * Math.ceil(min / ruler_scale) - min
    # for i in [ruler_start...duration] by ruler_scale
    #     x = i / duration * WIDTH
    #     ctx.drawText
    #         x: x
    #         y: 10
    #         fillStyle: "#aaa"
    #         strokeWidth: 0
    #         fontSize: "0.8em"
    #         text: "#{Math.round i + min}ms"
    #         fromCenter: true
    #         maxWidth: 1000
    #     ctx.drawLine
    #         strokeStyle: '#aaa'
    #         strokeWidth: 1
    #         x1: x
    #         y1: 20
    #         x2: x
    #         y2: HEIGHT

    active_stack = [] # unfinished frames
    active_count = 0 # number of active frames in active_stack
    mergeable_frames = [] # finished frames waiting to be merged
    drawn_frames = []
    skip_count = 0 # number of active frames that we should skip

    _drawFrame = (frame) ->
        x = WIDTH * frame.left
        y = HEIGHT - (frame.top + 1) * FRAME_STRIDE

        return if frame.skip
        return if y < HEADER_HEIGHT

        width = WIDTH * (frame.right - frame.left)
        height = FRAME_HEIGHT
        color = chroma.hsl(
            222 - 222 * Math.atan((frame.multiplicity or 0) / 20) * 2 / Math.PI, 0.55, 0.55)
        if not frame.marked
            lch = color.lch()
            lch[1] = 0
            color = chroma.lch lch
        label = frame.label

        ctx.fillStyle = color.hex()
        ctx.fillRect x, y, width, height
        ctx.strokeStyle = color.darken().hex()
        ctx.strokeRect x, y, width, height

        if not frame.multiplicity and width > 4 * MIN_FRAME_WIDTH
            metrics = ctx.measureText label
            if metrics.width + 2 * MIN_FRAME_WIDTH <= width
                ctx.fillStyle = "#fff"
                ctx.fillText label,
                    x + (width - metrics.width) / 2,
                    y + (height - FONT_HEIGHT) / 2

        drawn_frames.push
            left: x
            right: x + width
            top: y
            bottom: y + height
            label: label
            labels: frame.labels
            multiplicity: frame.multiplicity
            duration: (frame.right - frame.left) * duration

    # prefill with frames that started to the left of view
    for i in [0...start] by 1
        label = getLabel thread, thread.trace.data[i][0]
        skip = skipLabel label
        if not label.length
            # popping a frame; discard from active stack
            active_count = Math.max active_count - 1, 0
            skip_count-- if active_count >= 0 and active_stack[active_count].skip
            continue
        # pushing an unfinished frame
        active_stack.push null while active_count >= active_stack.length
        active_stack[active_count] =
            label: label
            left: 0
            right: 0
            top: active_count - skip_count
            marked: not options.filter
            skip: skip
        if options.filter and label.toLowerCase().indexOf(options.filter) >= 0
            for f in active_stack
                f.marked = true
        active_count++
        skip_count++ if skip

    # draw frames within view
    for i in [start...end] by 1
        label = getLabel thread, thread.trace.data[i][0]
        skip = skipLabel label
        pos = (thread.trace.data[i][1] - min) / duration
        if label.length
            # push an unfinished frame onto stack
            active_stack.push null while active_count >= active_stack.length
            active_stack[active_count] =
                label: label
                left: pos
                right: 0
                top: active_count - skip_count
                marked: not options.filter
                skip: skip
            if options.filter and label.toLowerCase().indexOf(options.filter) >= 0
                for f in active_stack
                    f.marked = true
            active_count++
            skip_count++ if skip
            continue

        if not active_count
            continue

        # popping a frame; finish the frame
        active_count--
        frame = active_stack[active_count]
        frame.right = pos
        skip_count-- if frame.skip

        if pos - frame.left < MIN_FRAME_WIDTH
            # save for merging later
            mergeable_frames.push null while frame.top >= mergeable_frames.length
            merger = mergeable_frames[frame.top]
            if frame.left - merger?.right < MIN_FRAME_WIDTH
                # merge with previous frame
                merger.right = pos
                merger.multiplicity = (merger.multiplicity or 1) + 1
                merger.labels[frame.label] = (merger.labels[frame.label] or 0) + 1
                merger.marked = merger.marked or frame.marked
                merger.skip = false
                continue

            if merger and merger.right - merger.left >= MIN_FRAME_WIDTH
                # draw the previous merged frame
                _drawFrame merger

            frame.labels = {}
            frame.labels[frame.label] = 1
            # replace previous unmerged frame
            mergeable_frames[frame.top] = frame
            continue

        # draw now
        _drawFrame frame

    # finish all remaining frames
    for merger in mergeable_frames
        if merger and merger.right - merger.left >= MIN_FRAME_WIDTH
            _drawFrame merger

    while active_count-- > 0
        frame = active_stack[active_count]
        frame.right = 1
        _drawFrame frame

    drawn_frames.sort (a, b) -> a.right - b.right

initialize = (thread) ->
    elems =
        container: $(".traceview .plot-container")
        plot: $(".traceview .plot")
        tooltip: $(".traceview .tooltip")
        marker: $(".traceview .marker")
        timestamp: $(".traceview .marker .timestamp")
        slider: $(".traceview .slider")
        table: $(".stats tbody")
        filter: $(".filter")
    elems.plot.attr "width", elems.slider.width() # also clears the canvas
    elems.marker.height elems.plot.height()

    dragging = null
    setSlider elems, thread

    options =
        range: elems.slider.rangeSlider "values"
        filter: elems.filter.val()

    redraw elems, thread, options
    elems.slider.on "valuesChanging", (e, data) ->
        window.requestAnimationFrame () ->
            dragging = null
            elems.marker.hide()
            options.range = data.values
            redraw elems, thread, options
    elems.filter.on "input", (e) ->
        window.requestAnimationFrame () ->
            options.filter = elems.filter.val()
            redraw elems, thread, options

    populateTiming elems, thread, options.range
    elems.slider.on "valuesChanged", (e, data) ->
        options.range = data.values
        populateTiming elems, thread, options.range

    mousemove = (e) ->
        TOOLTIP_SPACING = 10
        plotOffset = elems.plot.offset()
        [x, y] = [e.pageX - plotOffset.left, e.pageY - plotOffset.top]
        start = binarySearch drawn_frames, x, (f) -> f?.right
        range = elems.slider.rangeSlider "values"

        if dragging and not dragging.stopped
            dragging_width = Math.abs e.pageX - dragging.x
            elems.timestamp.text "<#{smartTime dragging_width / elems.plot.width() *
                                     (range.max - range.min) / 1e3}>"
            elems.marker.removeClass("zoomin").width Math.max(1, dragging_width)
            elems.marker.offset
                left: Math.min e.pageX, dragging.x
                top: plotOffset.top
            return

        if not dragging or not dragging.stopped
            elems.timestamp.text "#{Math.round(x / elems.plot.width() *
                                    (range.max - range.min) + range.min)}ms"
            elems.marker.removeClass("zoomin").width(1).show().offset
                left: e.pageX
                top: plotOffset.top
        else
            elems.marker.addClass("zoomin")
            markerOffset = elems.marker.offset()
            if (e.pageX > markerOffset.left and
                    e.pageX < markerOffset.left + elems.marker.width())
                elems.tooltip.hide()
                return

        for i in [start...drawn_frames.length] by 1
            frame = drawn_frames[i]
            if x <= frame.left or y <= frame.top or y > frame.bottom
                continue

            if frame.labels
                label = "#{frame.multiplicity} labels:<br><br>"
                labels = Object.keys frame.labels
                labels.sort (a, b) ->
                    frame.labels[b] - frame.labels[a]
                label += ("#{frame.labels[l]} &times; " +
                          "#{escapeHTML(l)}<br>" for l in labels[...3]).join ""
            else
                label = escapeHTML(frame.label)
            label += "<br>spanning #{smartTime frame.duration / 1e3}"

            elems.tooltip.children(".tooltip-inner").html label
            elems.tooltip.show().offset(
                left: Math.max(TOOLTIP_SPACING,
                    Math.min(elems.plot.width() - elems.tooltip.width(),
                    plotOffset.left + (frame.right + frame.left - elems.tooltip.width()) / 2))
                top: plotOffset.top + frame.top - elems.tooltip.height() - TOOLTIP_SPACING)
            return

        elems.tooltip.hide()

    mouseout = (e) ->
        elems.tooltip.hide()
        if dragging
            dragging.stopped = true
            return
        elems.marker.hide()

    mousedown = (e) ->
        if elems.tooltip.is(':visible')
            return

        markerOffset = elems.marker.offset()
        markerWidth = elems.marker.width()
        if (dragging?.stopped and e.pageX > markerOffset.left and
                e.pageX < markerOffset.left + markerWidth)
            plotOffset = elems.plot.offset()
            plotWidth = elems.plot.width()
            range = elems.slider.rangeSlider "values"
            dragging = null
            offsetToValue = (offset) ->
                (offset - plotOffset.left) / plotWidth * (range.max - range.min) + range.min
            newRange =
                min: offsetToValue(markerOffset.left)
                max: offsetToValue(markerOffset.left + markerWidth)
            elems.slider.rangeSlider "values", newRange.min, newRange.max
            elems.slider.trigger "valuesChanging",
                values: newRange
            elems.slider.trigger "valuesChanged",
                values: newRange
            mousemove e
            return

        dragging =
            x: e.pageX
            y: e.pageY
        mousemove e
        e.preventDefault()

    mouseup = (e) ->
        if not dragging
            return
        if Math.abs(e.pageX - dragging.x) < 2 and Math.abs(e.pageY - dragging.y) < 2
            dragging = null
            mousemove e
            return
        dragging.stopped = true

    elems.container.mousemove mousemove
    elems.container.mouseleave mouseout
    elems.container.mousedown mousedown
    elems.container.mouseup mouseup

$ ->
    tracefile = $("#tracefile")
    tracefile.change () ->
        $.getJSON tracefile.val()
            .done (file) -> initialize(file.threads[0])
    tracefile.trigger "change"
