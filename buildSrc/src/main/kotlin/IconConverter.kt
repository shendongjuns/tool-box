import org.apache.batik.transcoder.TranscoderInput
import org.apache.batik.transcoder.TranscoderOutput
import org.apache.batik.transcoder.image.PNGTranscoder
import org.gradle.api.DefaultTask
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.TaskAction
import java.awt.Color
import java.awt.Graphics2D
import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import javax.imageio.ImageIO

abstract class IconConverter : DefaultTask() {

    @get:InputFile
    abstract val svgFile: RegularFileProperty

    @get:OutputFile
    abstract val icoFile: RegularFileProperty

    @TaskAction
    fun convert() {
        val svg = svgFile.get().asFile
        val ico = icoFile.get().asFile
        ico.parentFile.mkdirs()

        val sizes = intArrayOf(16, 32, 48, 256)
        val images = sizes.map { size ->
            val pngBytes = renderSvgToPng(svg, size)
            ImageIO.read(ByteArrayInputStream(pngBytes))
        }
        writeIco(images, sizes, ico)
        println("图标已生成: ${ico.absolutePath}")
    }

    private fun renderSvgToPng(svg: File, size: Int): ByteArray {
        val transcoder = PNGTranscoder().apply {
            addTranscodingHint(PNGTranscoder.KEY_WIDTH, size.toFloat())
            addTranscodingHint(PNGTranscoder.KEY_HEIGHT, size.toFloat())
            addTranscodingHint(PNGTranscoder.KEY_BACKGROUND_COLOR, Color.WHITE)
        }
        val output = ByteArrayOutputStream()
        transcoder.transcode(
            TranscoderInput(svg.toURI().toString()),
            TranscoderOutput(output)
        )
        return output.toByteArray()
    }

    private fun writeIco(images: List<BufferedImage>, sizes: IntArray, output: File) {
        val bos = ByteArrayOutputStream()
        bos.write(shortLE(0))
        bos.write(shortLE(1))
        bos.write(shortLE(images.size))

        var dataOffset = 6 + 16 * images.size
        val imageData = mutableListOf<ByteArray>()

        for ((i, img) in images.withIndex()) {
            val square = if (img.width == sizes[i] && img.height == sizes[i]) img
            else {
                val s = BufferedImage(sizes[i], sizes[i], BufferedImage.TYPE_INT_ARGB)
                val g = s.createGraphics()
                g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
                g.drawImage(img, 0, 0, sizes[i], sizes[i], null)
                g.dispose(); s
            }
            val bmp = toBmpData(square)
            imageData.add(bmp)
            val sz = sizes[i].coerceAtMost(256)
            bos.write(sz); bos.write(sz)
            bos.write(0); bos.write(0)
            bos.write(shortLE(1))
            bos.write(shortLE(32))
            bos.write(intLE(bmp.size))
            bos.write(intLE(dataOffset))
            dataOffset += bmp.size
        }
        for (d in imageData) bos.write(d)
        output.writeBytes(bos.toByteArray())
    }

    private fun toBmpData(img: BufferedImage): ByteArray {
        val w = img.width; val h = img.height
        val bos = ByteArrayOutputStream()
        bos.write(intLE(40))
        bos.write(intLE(w)); bos.write(intLE(h * 2))
        bos.write(shortLE(1)); bos.write(shortLE(32))
        bos.write(intLE(0)); bos.write(intLE(0))
        bos.write(intLE(0)); bos.write(intLE(0))
        bos.write(intLE(0)); bos.write(intLE(0))

        for (y in (h - 1) downTo 0)
            for (x in 0 until w) {
                val argb = img.getRGB(x, y)
                bos.write((argb shr 16) and 0xFF)
                bos.write((argb shr 8) and 0xFF)
                bos.write(argb and 0xFF)
                bos.write((argb shr 24) and 0xFF)
            }

        val rowBytes = (w + 7) / 8
        for (y in (h - 1) downTo 0) {
            val row = ByteArray(rowBytes)
            for (x in 0 until w)
                if (((img.getRGB(x, y) shr 24) and 0xFF) == 0)
                    row[x / 8] = (row[x / 8].toInt() or (1 shl (7 - (x % 8)))).toByte()
            bos.write(row)
            val pad = (4 - rowBytes % 4) % 4
            repeat(pad) { bos.write(0) }
        }
        return bos.toByteArray()
    }

    private fun shortLE(v: Int) = byteArrayOf((v and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte())
    private fun intLE(v: Int) = byteArrayOf(
        (v and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte(),
        ((v shr 16) and 0xFF).toByte(), ((v shr 24) and 0xFF).toByte()
    )
}
