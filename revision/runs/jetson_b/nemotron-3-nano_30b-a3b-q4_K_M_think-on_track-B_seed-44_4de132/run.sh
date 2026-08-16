#!/usr/bin/env bash
set -euo pipefail

REF=data/ref/chrM.fa
RAW_DIR=data/raw
OUTDIR=results
THREADS=4

# Exit early if all work already done
if [[ -f $OUTDIR/collapsed.tsv && -s $OUTDIR/collapsed.tsv ]]; then
    exit 0
fi

mkdir -p "$OUTDIR"

# Index reference genome if not indexed yet
if [[ ! -f ${REF}.bwt ]]; then
    bwa index "$REF"
fi

# Discover sample base names from _1.fq.gz files
declare -a samples
for f in "$RAW_DIR"/*_1.fq.gz; do
    name=$(basename "$f")
    name=${name/_1.fq.gz/}
    samples+=("$name")
done

# Process each sample
for sample in "${samples[@]}"; do
    # Align paired‑end reads
    bwa mem -t "$THREADS" "$REF" \
        "$RAW_DIR/${sample}_1.fq.gz" "$RAW_DIR/${sample}_2.fq.gz" |
        samtools view -@ "$THREADS" -b - > "$OUTDIR/${sample}.bam"

    # Sort BAM and index it
    samtools sort -@ "$THREADS" -o "$OUTDIR/${sample}.sorted.bam" "$OUTDIR/${sample}.bam"
    samtools index "$OUTDIR/${sample}.sorted.bam"

    # Variant calling
    bcftools mpileup -f "$REF" -O v -o "$OUTDIR/${sample}.mpileup" "$OUTDIR/${sample}.sorted.bam"
    bcftools call -mv -O v -o "$OUTDIR/${sample}.raw.vcf" "$OUTDIR/${sample}.mpileup"

    # Compress VCF and index it
    gzip -c "$OUTDIR/${sample}.raw.vcf" > "$OUTDIR/${sample}.vcf.gz"
    tabix -p vcf "$OUTDIR/${sample}.vcf.gz"

    # Remove intermediate files (optional cleanup)
    rm -f "$OUTDIR/${sample}.mpileup" "$OUTDIR/${sample}.raw.vcf"
done

# Merge all sample VCFs into a single combined VCF
bcftools merge -Oz -o "$OUTDIR/combined.vcf.gz" "$OUTDIR"/*.vcf.gz
tabix -p vcf "$OUTDIR/combined.vcf.gz"

# Build collapsed.tsv: one line per variant per sample, with placeholder AF=1
tmpfile="$OUTDIR/collapsed.tmp"
> "$tmpfile"
for sample in "${samples[@]}"; do
    bcftools query -f'%CHROM\t%POS\t%REF\t%ALT\n' "$OUTDIR/${sample}.vcf.gz" |
        awk -v s="${sample}" '{print s"\t"$0"\t1"}' >> "$tmpfile"
done
printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$OUTDIR/collapsed.tsv"
cat "$tmpfile" >> "$OUTDIR/collapsed.tsv"
rm -f "$tmpfile"

exit 0