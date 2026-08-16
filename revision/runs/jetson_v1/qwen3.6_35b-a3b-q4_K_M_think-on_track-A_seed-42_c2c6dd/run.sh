#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF=data/ref/chrM.fa
RAW=data/raw
OUTDIR=results

mkdir -p "$OUTDIR"

# 2. Reference indexing
if [ ! -f "${REF}.fai" ] || [ ! -f "${REF}.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# 3-7. Per-sample processing
for sample in "${SAMPLES[@]}"; do
    if [ -f "${OUTDIR}/${sample}.vcf.gz.tbi" ]; then
        continue
    fi

    # 3 & 4. Alignment and sorting
    bwa mem -t "$THREADS" \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$REF" "${RAW}/${sample}_1.fq.gz" "${RAW}/${sample}_2.fq.gz" | \
        samtools sort -@ "$THREADS" -o "${OUTDIR}/${sample}.bam"

    # 5. BAM indexing
    samtools index -@ "$THREADS" "${OUTDIR}/${sample}.bam"

    # 6. Variant calling
    lofreq call-parallel --pp-threads "$THREADS" \
        -f "$REF" -o "${OUTDIR}/${sample}.vcf" "${OUTDIR}/${sample}.bam"

    # 7. VCF compression and indexing
    bgzip -c "${OUTDIR}/${sample}.vcf" > "${OUTDIR}/${sample}.vcf.gz"
    tabix -p vcf "${OUTDIR}/${sample}.vcf.gz"
    rm -f "${OUTDIR}/${sample}.vcf"
done

# 8. Collapse step
if [ ! -f "${OUTDIR}/collapsed.tsv" ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${OUTDIR}/collapsed.tsv"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "${OUTDIR}/${sample}.vcf.gz" >> "${OUTDIR}/collapsed.tsv"
    done
fi