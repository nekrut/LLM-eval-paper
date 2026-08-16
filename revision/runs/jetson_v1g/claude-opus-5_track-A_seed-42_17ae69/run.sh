#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUT=results

mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# Step 2: reference indexing (once)
# ---------------------------------------------------------------------------
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

bwa_index_ok=1
for ext in amb ann bwt pac sa; do
    if [ ! -s "${REF}.${ext}" ]; then
        bwa_index_ok=0
    fi
done
if [ "$bwa_index_ok" -eq 0 ]; then
    bwa index "$REF"
fi

# ---------------------------------------------------------------------------
# Steps 3-7: per-sample alignment, sorting, indexing, calling, compression
# ---------------------------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
    r1="${RAW}/${sample}_1.fq.gz"
    r2="${RAW}/${sample}_2.fq.gz"
    bam="${OUT}/${sample}.bam"
    bai="${OUT}/${sample}.bam.bai"
    vcf="${OUT}/${sample}.vcf"
    vcfgz="${OUT}/${sample}.vcf.gz"
    tbi="${OUT}/${sample}.vcf.gz.tbi"

    # Step 3-4: bwa mem | samtools sort
    if [ ! -s "$bam" ] || [ "$r1" -nt "$bam" ] || [ "$r2" -nt "$bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$r1" "$r2" \
            | samtools sort -@ "$THREADS" -o "${bam}.tmp"
        mv -f "${bam}.tmp" "$bam"
        rm -f "$bai"
    fi

    # Step 5: BAM index
    if [ ! -s "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    # Step 6-7: lofreq call-parallel, bgzip, tabix
    if [ ! -s "$vcfgz" ] || [ "$bam" -nt "$vcfgz" ]; then
        rm -f "$vcf" "$vcfgz" "$tbi"
        lofreq call-parallel --pp-threads "$THREADS" \
            --ref "$REF" --out "$vcf" \
            "$bam"
        bgzip -f "$vcf"
        rm -f "$vcf"
        rm -f "$tbi"
    fi

    if [ ! -s "$tbi" ] || [ "$vcfgz" -nt "$tbi" ]; then
        tabix -f -p vcf "$vcfgz"
    fi
done

# ---------------------------------------------------------------------------
# Step 8: collapse to a single TSV
# ---------------------------------------------------------------------------
collapsed="${OUT}/collapsed.tsv"
rebuild=0
if [ ! -s "$collapsed" ]; then
    rebuild=1
else
    for sample in "${SAMPLES[@]}"; do
        if [ "${OUT}/${sample}.vcf.gz" -nt "$collapsed" ]; then
            rebuild=1
        fi
    done
fi

if [ "$rebuild" -eq 1 ]; then
    tmp="${collapsed}.tmp"
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp"
    for sample in "${SAMPLES[@]}"; do
        bcftools query \
            -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "${OUT}/${sample}.vcf.gz" >> "$tmp"
    done
    mv -f "$tmp" "$collapsed"
fi