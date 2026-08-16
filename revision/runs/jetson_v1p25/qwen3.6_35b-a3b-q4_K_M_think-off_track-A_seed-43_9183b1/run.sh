#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.amb ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# 3-7. Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if all outputs exist and are newer than inputs
    if [ -f "$bai" ] && [ -f "$tbi" ]; then
        # Check if any input is newer
        need_rebuild=0
        for fq in "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz"; do
            if [ "$fq" -nt "$bai" ] || [ "$fq" -nt "$tbi" ]; then
                need_rebuild=1
                break
            fi
        done
        if [ "$need_rebuild" -eq 0 ]; then
            continue
        fi
    fi

    # 3. Alignment
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        data/ref/chrM.fa \
        "data/raw/${sample}_1.fq.gz" \
        "data/raw/${sample}_2.fq.gz" | \
    # 4. Sort BAM
    samtools sort -@ $THREADS -o "$bam" -

    # 5. Index BAM
    samtools index -@ $THREADS "$bam"

    # 6. Variant calling with lofreq
    vcf="results/${sample}.vcf"
    if [ ! -f "$vcf" ] || [ "data/ref/chrM.fa" -nt "$vcf" ] || [ "$bai" -nt "$vcf" ]; then
        lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o "$vcf" "$bam"
    fi

    # 7. Compress and index VCF
    if [ ! -f "$vcf_gz" ] || [ "$vcf" -nt "$vcf_gz" ]; then
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# 8. Collapse step
collapsed="results/collapsed.tsv"
need_collapse=0
for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        need_collapse=1
        break
    fi
done

if [ "$need_collapse" -eq 1 ] || { [ -f "$collapsed" ] && ls results/*.vcf.gz | while read f; do if [ "$f" -nt "$collapsed" ]; then exit 0; fi; done; }; then
    # Rebuild collapsed.tsv
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi